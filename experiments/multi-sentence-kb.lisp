;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; multi-sentence-kb.lisp -- what happens when more than one sentence is in the
;;; room.
;;;
;;; EVERY test in test/ takes ONE sentence to ONE graph and stops. cgraph's
;;; reasoning half -- project, maximal-join, query over a context, say-query-
;;; results -- has never been pointed at extracted graphs at all. This file does
;;; that, and it is an EXPERIMENT, not a gate: its output is findings, and a
;;; surprising result is a result, not a failure. Nothing in the system depends
;;; on it.
;;;
;;; It measures four things, in order of how much they decide whether CGs are
;;; reasonable to build an application on:
;;;
;;;   1. INTAKE     -- of a corpus written in the register the parser supports
;;;                    and the vocabulary the ontology types, how much gets in?
;;;   2. ACCUMULATION -- put those graphs in one context. Does the knowledge base
;;;                    stay a faithful record of what was said?
;;;   3. IDENTITY   -- is Sue in sentence 1 the same Sue as in sentence 5? A
;;;                    knowledge base that cannot say so is a pile of sentences.
;;;   4. RETRIEVAL  -- query the store and say the answers back in English.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :cg-from-parse)' \
;;;     --load experiments/multi-sentence-kb.lisp
;;;
;;; From a live session: (cg-from-parse::run-kb-experiment)
;;;
;;; 2026-09-28: THE FIX IN SECTION 6 HAS LANDED, in the emitter rather than as a
;;; post-pass -- system/identity.lisp. Re-running this file now measures the real
;;; thing, and it reaches section 6's predicted numbers on the way in: "Sue" 1 id,
;;; same-individual-p T, 24 graphs -> 2, zero events wrongly merged. Section 6
;;; itself is kept because a prediction that was made BEFORE the build and then
;;; met is worth more than one written afterwards; it now individuates graphs
;;; that are already individuated, which is a no-op, not a second measurement.

(in-package :cg-from-parse)

;;; --- The corpus ------------------------------------------------------------
;;; One small domain -- two people, a household, a day. Every content word is
;;; BOTH in PARSIFAL's lexicon and in the mounted ontology, so this runs strict
;;; (*on-missing-type* :error): nothing is invented to make a sentence work, and
;;; a sentence that cannot be typed is reported rather than papered over.
;;;
;;; Constructions are spread deliberately across what the extractor claims to
;;; handle, one per line, so the intake number below means something.

(defparameter *kb-corpus*
  '(("Sue eats a pie ."                            . :transitive)
    ("Bob eats a hamburger ."                      . :transitive)
    ("the girl eats a pie ."                       . :transitive)
    ("Sue drives an automobile ."                  . :transitive)
    ("Sue drives the automobile to Baltimore ."    . :licensed-pp)
    ("Bob gives Sue a book ."                      . :ditransitive)
    ("Sue gives the book to the girl ."            . :ditransitive-pp)
    ("Sue sees the dog ."                          . :transitive)
    ("the dog sees Bob ."                          . :transitive)
    ("Sue has a dog ."                             . :possession)
    ("Sue 's dog sees the man ."                   . :genitive)
    ("Sue drives her automobile ."                 . :possessive-pronoun)
    ("Bob buys a hamburger ."                      . :exchange)
    ("Bob sells the automobile ."                  . :exchange)
    ("Sue pays Bob a dollar ."                     . :exchange)
    ("the man knows that Sue eats a pie ."         . :complement)
    ("the woman eats lunch ."                      . :transitive)
    ("the man eats breakfast in the kitchen ."     . :pp-adjunct-loc)
    ("Sue eats dinner on Monday ."                 . :pp-adjunct-time)
    ("the child sees a red ball ."                 . :adjective)
    ("Sue is eating a pie ."                       . :progressive)
    ("Sue will drive to Baltimore ."               . :future)
    ("the boy that Sue sees eats a hamburger ."    . :relative)
    ("Bob attends a party ."                       . :transitive)
    ("the woman gives the boy a book ."            . :ditransitive)
    ("a pie is eaten by Sue ."                     . :passive))
  "(SENTENCE . CONSTRUCTION). Written to be INSIDE the supported register on
   purpose -- the coverage question is settled elsewhere (notes/parser-front-ends.md);
   what is being measured here is everything that happens AFTER a sentence parses.")

;;; --- Phase 1: intake -------------------------------------------------------

(defun kb-ingest (&key (corpus *kb-corpus*) (stream *standard-output*))
  "Parse and extract every sentence in CORPUS. Returns (values ENTRIES FAILURES),
   where ENTRIES is a list of (SENTENCE CONSTRUCTION GRAPH) and FAILURES a list of
   (SENTENCE CONSTRUCTION REASON). Strict typing: a lemma outside the ontology is
   a failure, not an invention."
  (let ((entries '()) (failures '()))
    (dolist (row corpus)
      (destructuring-bind (sentence . construction) row
        (handler-case
            (handler-bind ((warning #'muffle-warning))
              (let ((graph (parse-and-extract sentence :on-missing :error)))
                (push (list sentence construction graph) entries)))
          (error (e)
            (push (list sentence construction
                        (first (split-lines (princ-to-string e))))
                  failures)))))
    (setf entries (nreverse entries) failures (nreverse failures))
    (format stream "~&~%=== 1. INTAKE ===~%~d of ~d sentences extracted~%"
            (length entries) (length corpus))
    (when failures
      (format stream "~%  did NOT get in:~%")
      (dolist (f failures)
        (format stream "    ~s~%      (~a) ~a~%" (first f) (second f) (third f))))
    (values entries failures)))

(defun split-lines (string)
  "STRING's lines. Only used to keep a multi-line error report to its first line."
  (loop for start = 0 then (1+ pos)
        for pos = (position #\Newline string :start start)
        collect (subseq string start pos)
        while pos))

;;; --- Phase 2: accumulation -------------------------------------------------
;;; Two stores, the same graphs. INCLUDE-CGRAPH combines on the way in (that is
;;; what it is for); the flat store just holds them. The difference between the
;;; two IS the finding.

(defun kb-store (entries &key join)
  "A context holding ENTRIES' graphs. With :JOIN t they go through
   INCLUDE-CGRAPH, which combines a graph with any it shares concepts with; else
   each is added as-is."
  (let ((kb (cg::make-context)))
    (dolist (entry entries)
      (let ((graph (third entry)))
        (if join
            (cg::include-cgraph graph kb)
            (push graph (cg::graphs kb)))))
    (setf (cg::graphs kb) (reverse (cg::graphs kb)))
    kb))

(defun arc-label-tally (graph &key events-only)
  "For each concept in GRAPH, how many arcs of each relation label leave it:
   an alist ((CONCEPT-TEXT (LABEL . COUNT) ...) ...) for labels seen more than
   once.

   WHICH concept repeats is the whole distinction. Two `agnt' arcs off one EVENT
   means a join merged two events the text kept apart -- one eating cannot have
   two eaters. Two `agnt' arcs off a PERSON means she is the agent of two events,
   which is a knowledge base doing its job. :EVENTS-ONLY asks the first question."
  (let ((rows '()))
    (dolist (node (cg::nodes graph))
      (when (and (typep node 'cg::concept)
                 (or (not events-only) (event-concept-p node)))
        (let ((counts (make-hash-table :test 'equal)))
          (dolist (rel (cg::outarcs node))
            (let ((label (string (cg::label (cg::relation-type rel)))))
              (incf (gethash label counts 0))))
          (let ((dups (loop for l being the hash-keys of counts using (hash-value n)
                            when (> n 1) collect (cons l n))))
            (when dups
              (push (cons (cg::format-node node) dups) rows))))))
    (nreverse rows)))

(defun kb-report-accumulation (entries &key (stream *standard-output*))
  "Put ENTRIES' graphs in one context THROUGH include-cgraph, and report what
   that did to the knowledge. Returns the joined store. Consumes ENTRIES: the
   combination is destructive, so these graphs are not reusable afterwards."
  (let ((joined (kb-store entries :join t)))
    (format stream "~%=== 2. ACCUMULATION ===~%")
    (format stream "  ~d graphs in, ~d graph(s) after include-cgraph~%~
                    ~2t(combining is destructive -- the input graphs are rewired in place)~%"
            (length entries) (length (cg::graphs joined)))
    (let ((merged '()))
      (dolist (graph (cg::graphs joined))
        (let ((dups (arc-label-tally graph :events-only t)))
          (when dups (push (cons graph dups) merged))))
      (cond ((null merged)
             (format stream "  no concept carries two arcs of one relation.~%"))
            (t
             (format stream "~%  ~d graph(s) carry an EVENT with a repeated relation --~%~
                             ~10tone eating cannot have two eaters, so these are events~%~
                             ~10tthe join merged that the text kept apart:~%"
                     (length merged))
             (dolist (m (reverse merged))
               ;; NOT printing the graph: when everything merges, it is pages
               ;; long and unreadable, which is itself the point.
               (dolist (row (remove-duplicates (cdr m) :test #'equal :key #'car))
                 (format stream "      ~a has ~{~{~a x~a~}~^, ~}~%"
                         (car row) (mapcar (lambda (d) (list (car d) (cdr d))) (cdr row))))))))
    joined))

;;; --- Phase 3: identity across sentences ------------------------------------

(defun kb-named-concepts (entries name)
  "Every concept in ENTRIES' graphs whose referent names NAME."
  (let ((found '()))
    (dolist (entry entries)
      (dolist (node (cg::nodes (third entry)))
        (when (and (typep node 'cg::concept)
                   (let ((ref (cg::referent node)))
                     (and ref (equal (ignore-errors (cg::referent-name node)) name))))
          (push (cons (first entry) node) found))))
    (nreverse found)))

(defun kb-report-identity (entries &key (name "Sue") (stream *standard-output*))
  "Does the knowledge base know that NAME in one sentence is NAME in the next?"
  (let* ((mentions (kb-named-concepts entries name))
         (ids (remove nil (mapcar (lambda (m)
                                    (ignore-errors
                                     (cg::id (cg::content (cg::referent (cdr m))))))
                                  mentions)))
         (distinct (remove-duplicates ids :test #'equal))
         (pairwise-same
           (when (> (length mentions) 1)
             (cg::same-individual-p (cdr (first mentions)) (cdr (second mentions))))))
    (format stream "~%=== 3. IDENTITY ACROSS SENTENCES ===~%")
    (format stream "  ~s is mentioned in ~d sentences, carrying ~d distinct individual id(s).~%"
            name (length mentions) (length distinct))
    (format stream "  same-individual-p on the first two mentions: ~a~%" pairwise-same)
    (format stream "  ids: ~{~a~^ ~}~%" distinct)
    (values mentions distinct)))

;;; --- Phase 4: retrieval ----------------------------------------------------

(defparameter *kb-queries*
  '(("[EAT]-(agnt)->[PERSON: *x]."      . "who eats?")
    ("[EAT]-(obj)->[PIE]."              . "what eating involves a pie?")
    ("[DRIVE]-(agnt)->[PERSON: *x]."    . "who drives?")
    ("[PERSON: *x]<-(agnt)<-[GIVE]."    . "who gives?")
    ("[DOG]<-(poss)<-[PERSON: *x]."     . "whose dog?"))
  "(PATTERN . GLOSS). Patterns are cgraph linear form with *x variables.")

(defun kb-query (pattern kb)
  "Run PATTERN against KB. Binds *package* to :CG -- the reader interns a
   bracketed [TYPE] in the CURRENT package, so from any other package every
   type in the pattern reads as unknown."
  (let ((*package* (find-package :conceptual-graphs)))
    (cg::query pattern kb)))

(defun kb-report-queries (kb label &key (queries *kb-queries*) (stream *standard-output*))
  (format stream "~%=== 4. RETRIEVAL (~a store) ===~%" label)
  (dolist (row queries)
    (destructuring-bind (pattern . gloss) row
      (let* ((results (handler-bind ((warning #'muffle-warning))
                        (ignore-errors (kb-query pattern kb))))
             (bindings (remove-duplicates
                        (mapcar (lambda (r)
                                  (mapcar (lambda (b)
                                            (format nil "~a=~a" (car b) (cg::format-node (cdr b))))
                                          (getf r :bindings)))
                                results)
                        :test #'equal))
             (said (handler-bind ((warning #'muffle-warning))
                     (ignore-errors
                      (let ((cg::*anaphora-cross-coref* t))
                        (cg::say-query-results results))))))
        (format stream "~%  ~a~%    ~a~%    ~d result(s), ~d distinct binding(s)~@[: ~{~{~a~^, ~}~^ | ~}~]~%"
                gloss pattern (length results) (length bindings)
                (subseq (remove nil bindings) 0 (min 8 (length (remove nil bindings)))))
        (when said
          (format stream "    said back: ~{~s~^ ~}~%" (remove-duplicates said :test #'equal)))))))

;;; --- Phase 5: a join we actually want --------------------------------------

(defun kb-report-deliberate-join (entries &key (stream *standard-output*))
  "MAXIMAL-JOIN two graphs that a reader WOULD merge -- same person, same verb --
   and two that a reader would not, and print both, so the difference between a
   join that adds knowledge and one that invents it is on one screen."
  (flet ((graph-for (sentence)
           (third (find sentence entries :key #'first :test #'string=))))
    (let ((a (graph-for "Sue eats a pie ."))
          (b (graph-for "Sue is eating a pie ."))
          (c (graph-for "Bob eats a hamburger .")))
      (format stream "~%=== 5. JOIN ===~%")
      (when (and a b)
        (format stream "~%  the same thing said twice:~%    ~s~%    ~s~%  joined ->~%~a~%"
                "Sue eats a pie ." "Sue is eating a pie ."
                (or (ignore-errors (cg::format-cgraph (cg::maximal-join a b))) "<error>")))
      (when (and a c)
        (format stream "~%  two DIFFERENT events:~%    ~s~%    ~s~%  joined ->~%~a~%"
                "Sue eats a pie ." "Bob eats a hamburger ."
                (or (ignore-errors (cg::format-cgraph (cg::maximal-join a c))) "<error>"))))))

;;; --- Phase 6: individuation ------------------------------------------------
;;; Phases 2 and 3 fail in opposite directions, and the hypothesis is that they
;;; are ONE failure: nothing in an extracted graph says WHICH thing it is about.
;;;
;;;   Events are GENERIC. [EAT] from one sentence and [EAT] from the next are
;;;   two concepts of one type with no referent, and joining those is exactly
;;;   what the formation rules license -- so every eating in the corpus becomes
;;;   one eating. The join is not wrong; the graphs do not say otherwise.
;;;
;;;   Individuals are FRESH. make-individual mints a new id per call, so each
;;;   sentence gets its own Sue and the store cannot say they are the same
;;;   person -- the same silence, read the other way.
;;;
;;; So: give each event an individual referent of its own, give each NAME one
;;; shared individual across the corpus, and run the same measurements again.
;;; This is done HERE, to the graphs, deliberately NOT in the extractor -- the
;;; question is what CG does once individuation exists, not what our emitter
;;; should do about it. (If the answer is good, that is the argument for doing
;;; it in the emitter.)

(defun event-concept-p (concept)
  "True when CONCEPT's type is an event -- what a sentence's predicate becomes."
  (cg::safe-subtype-p (cg::label (cg::concept-type concept)) 'cg::event))

(defun individuate-graph (graph name-registry)
  "Give GRAPH's concepts referents that IDENTIFY. Two moves:

   an event concept with no referent gets a fresh individual, so it is THIS
   eating rather than eating in general;

   a concept naming an individual gets the one canonical individual for that
   (type . name), taken from NAME-REGISTRY, so Sue is one person corpus-wide.

   Destructive. Returns GRAPH."
  (dolist (node (cg::nodes graph))
    (when (typep node 'cg::concept)
      (let* ((ctype (cg::concept-type node))
             (ref   (cg::referent node))
             (name  (and ref (ignore-errors (cg::referent-name node)))))
        (cond
          ((and name (stringp name) (plusp (length name)))
           (let* ((key (cons (cg::label ctype) name))
                  (canonical (or (gethash key name-registry)
                                 (setf (gethash key name-registry)
                                       (cg::content ref)))))
             (setf (cg::referent node) (cg::make-referent canonical))))
          ((and (null ref) (event-concept-p node))
           (setf (cg::referent node)
                 (cg::make-referent (cg::make-individual ctype))))))))
  graph)

(defun kb-report-individuated (entries &key (stream *standard-output*))
  "Re-run accumulation and identity over individuated graphs."
  (let ((registry (make-hash-table :test 'equal)))
    (dolist (entry entries) (individuate-graph (third entry) registry))
    (format stream "~%=== 6. THE SAME CORPUS, INDIVIDUATED ===~%")
    (format stream "  ~d distinct named individual(s) across the corpus~%"
            (hash-table-count registry))
    ;; identity, again
    (let* ((mentions (kb-named-concepts entries "Sue"))
           (ids (remove nil (mapcar (lambda (m)
                                      (ignore-errors
                                       (cg::id (cg::content (cg::referent (cdr m))))))
                                    mentions))))
      (format stream "  \"Sue\": ~d mentions, ~d distinct id(s); same-individual-p on the first two: ~a~%"
              (length mentions) (length (remove-duplicates ids :test #'equal))
              (when (> (length mentions) 1)
                (cg::same-individual-p (cdr (first mentions)) (cdr (second mentions))))))
    ;; a query BEFORE joining, so the comparison with phase 4 is like for like
    (let ((flat (kb-store entries :join nil)))
      (kb-report-queries flat "individuated, unjoined" :stream stream))
    ;; and now let the joiner loose on it
    (let ((joined (kb-store entries :join t)))
      (format stream "~%  include-cgraph on individuated graphs: ~d graphs in, ~d out~%"
              (length entries) (length (cg::graphs joined)))
      (let ((bad 0) (hubs 0))
        (dolist (graph (cg::graphs joined))
          (when (arc-label-tally graph :events-only t) (incf bad))
          (when (arc-label-tally graph) (incf hubs)))
        (format stream "  events with a repeated relation (merged events): ~d~%" bad)
        (format stream "  graphs with any repeated relation (incl. legitimate hubs): ~d~%" hubs)
        (dolist (graph (cg::graphs joined))
          (dolist (row (remove-duplicates (arc-label-tally graph :events-only t)
                                          :test #'equal :key #'car))
            (format stream "    residue: ~a has ~{~{~a x~a~}~^, ~}~%"
                    (car row) (mapcar (lambda (d) (list (car d) (cdr d))) (cdr row))))))
      (format stream "  (a COMMERCIAL-EXCHANGE with `part x2' is not a merge: the frame~%~
                      ~3thas two halves by construction -- goods one way, money the other.)~%")
      (kb-report-queries joined "individuated + joined" :stream stream))))

;;; --- The experiment --------------------------------------------------------

(defun run-kb-experiment (&key (corpus *kb-corpus*) (stream *standard-output*))
  "Run the whole thing and print the report. Returns the flat store's entries.

   EACH STORE GETS ITS OWN EXTRACTION, and that is not fastidiousness: combining
   is DESTRUCTIVE -- include-cgraph rewires the concepts of the graphs it merges,
   in place -- so a joined store and a flat store built from one extraction are
   the same objects, and measuring the flat one afterwards measures the joined
   one. (First run of this file did exactly that and reported Sue mentioned in
   900 sentences. The finding is real; the measurement was not.)"
  (ensure-cgraph) (ensure-domain-lexicon) (ensure-grammar)
  (format stream "~&~%############ multi-sentence KB experiment ############~%")
  (let ((entries (kb-ingest :corpus corpus :stream stream)))
    ;; flat store + every measurement that must see UNMERGED graphs
    (let ((flat (kb-store entries :join nil)))
      (kb-report-identity entries :stream stream)
      (kb-report-queries flat "flat" :stream stream))
    ;; a SECOND extraction to feed the joiner, since it will consume it
    (let* ((fresh (kb-ingest :corpus corpus :stream (make-broadcast-stream)))
           (joined (kb-report-accumulation fresh :stream stream)))
      (kb-report-queries joined "joined" :stream stream))
    ;; and a third, for the joins we run by hand
    (kb-report-deliberate-join (kb-ingest :corpus corpus :stream (make-broadcast-stream))
                               :stream stream)
    ;; a fourth: the same corpus with referents that identify
    (kb-report-individuated (kb-ingest :corpus corpus :stream (make-broadcast-stream))
                            :stream stream)
    (format stream "~%############ end ############~%")
    entries))

(run-kb-experiment)
