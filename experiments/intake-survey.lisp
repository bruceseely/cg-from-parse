;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; intake-survey.lisp -- WHICH LAYER refuses a sentence, and how often.
;;;
;;; multi-sentence-kb.lisp asked what happens to graphs AFTER they are built,
;;; on a corpus written to be inside the supported register on purpose. This
;;; file asks the question that one deliberately set aside: when a sentence
;;; does NOT get in, which of the four layers turned it away --
;;;
;;;   LEXICON   the parser has no entry for some word        (add a dict line)
;;;   GRAMMAR   every word is known and it still won't parse (real parser work)
;;;   ONTOLOGY/TYPE      it parsed, but a lemma has no concept type
;;;   ONTOLOGY/CONTRACT  it parsed and typed, and the LATTICE refused an arc
;;;   EXTRACTOR          everything upstream was fine and we broke
;;;
;;; That split is the whole point. `notes/parser-front-ends.md' argues the bill
;;; is mostly coverage rather than determinism, and `driver.lisp' already warns
;;; that "parsing on without the vocabulary you asked for is how a lexicon gap
;;; gets mistaken for a grammar gap." Neither has ever been MEASURED. A grammar
;;; gap is the only bucket that argues for changing parsers; a lexicon or
;;; ontology gap is an afternoon of data entry, and a CONTRACT refusal is the
;;; type system doing its job and belongs on the credit side of the ledger.
;;;
;;; Two bands, because one number would be rigged either way:
;;;   :A  in-register -- built only from words the parser AND the ontology both
;;;       know (61 of them; see the note on *survey-corpus*). Measures how
;;;       reliable the system is where it claims to work.
;;;   :B  stretch -- what a user would plausibly write next. Every :B row
;;;       carries an :EXPECT, so the report can show predicted vs. actual and a
;;;       wrong prediction is itself a finding.
;;;
;;; EXPERIMENT, not a gate. Its output is findings; a surprising result is a
;;; result. Nothing in the system depends on it.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :cg-from-parse)' \
;;;     --load experiments/intake-survey.lisp
;;;
;;; From a live session: (cg-from-parse::run-intake-survey)

(in-package :cg-from-parse)

;;; --- The corpus ------------------------------------------------------------
;;; Band A uses only the intersection of PARSIFAL's dictionary with the mounted
;;; ontology's labels. That intersection is 61 content words wide:
;;;
;;;   act ask attend automobile ball baltimore book bottle box boy bread
;;;   breakfast buy cheese cherry child dinner dog dollar drive eat friday fruit
;;;   girl give gladly hamburger hope house kitchen know letter lunch man manner
;;;   monday party pay person pick-up pie place quickly red rock saturday see
;;;   sell sit soup sunday tell thought thursday today tomorrow tuesday water
;;;   wednesday woman yesterday
;;;
;;; 432 further dictionary words (car, cat, friend, meet, hit, like, believe,
;;; arrive, ...) parse but have no concept type -- which is why band B can probe
;;; the ontology layer without inventing anything.

(defparameter *survey-corpus*
  '(;; ---------------- band A: in-register ----------------
    ("Sue eats a pie ."                                 :transitive        :a)
    ("Bob eats a hamburger ."                           :transitive        :a)
    ("the girl eats bread ."                            :transitive        :a)
    ("the man eats cheese ."                            :transitive        :a)
    ("the child eats soup ."                            :transitive        :a)
    ("the woman sees the dog ."                         :transitive        :a)
    ("the boy sees a rock ."                            :transitive        :a)
    ("Sue sees the box ."                               :transitive        :a)
    ("the dog sees the ball ."                          :transitive        :a)
    ("Bob drives an automobile ."                       :transitive        :a)
    ("the child sees a red ball ."                      :adjective         :a)
    ("Sue eats a red cherry ."                          :adjective         :a)
    ("Sue eats a cherry pie ."                          :compound          :a)
    ("the girl eats a fruit pie ."                      :compound          :a)
    ("Bob gives Sue a book ."                           :ditransitive      :a)
    ("the woman gives the boy a book ."                 :ditransitive      :a)
    ("Sue gives the girl a dollar ."                    :ditransitive      :a)
    ("Sue gives the book to the girl ."                 :ditransitive-pp   :a)
    ("Bob gives a dollar to the man ."                  :ditransitive-pp   :a)
    ("Sue has a dog ."                                  :possession        :a)
    ("the girl has a ball ."                            :possession        :a)
    ("the boy has a book ."                             :possession        :a)
    ("Sue 's dog sees the man ."                        :genitive          :a)
    ("the girl 's dog sees Bob ."                       :genitive          :a)
    ("the woman 's child eats a pie ."                  :genitive          :a)
    ("Sue drives her automobile ."                      :possessive-pronoun :a)
    ("Bob sells his automobile ."                       :possessive-pronoun :a)
    ("the boy eats his lunch ."                         :possessive-pronoun :a)
    ("Bob buys a hamburger ."                           :exchange          :a)
    ("Sue sells the automobile ."                       :exchange          :a)
    ("Sue pays Bob a dollar ."                          :exchange          :a)
    ("the man buys a book ."                            :exchange          :a)
    ("the man knows that Sue eats a pie ."              :complement        :a)
    ("Bob knows that the girl sees a dog ."             :complement        :a)
    ("Sue hopes that Bob buys a book ."                 :complement        :a)
    ("the man eats breakfast in the kitchen ."          :pp-adjunct-loc    :a)
    ("the woman eats lunch in the house ."              :pp-adjunct-loc    :a)
    ("Sue eats dinner on Monday ."                      :pp-adjunct-time   :a)
    ("Bob eats breakfast on Sunday ."                   :pp-adjunct-time   :a)
    ("the girl sees the dog today ."                    :bare-temporal     :a)
    ("Sue drives the automobile to Baltimore ."         :licensed-pp       :a)
    ("Bob drives to Baltimore ."                        :licensed-pp       :a)
    ("Sue is eating a pie ."                            :progressive       :a)
    ("the boy is driving an automobile ."               :progressive       :a)
    ("Sue will drive to Baltimore ."                    :future            :a)
    ("Bob will buy a book ."                            :future            :a)
    ("a pie is eaten by Sue ."                          :passive           :a)
    ("a hamburger is eaten by the dog ."                :passive           :a)
    ("Sue eats quickly ."                               :adverb            :a)
    ("Bob gives Sue a book gladly ."                    :adverb            :a)
    ("the boy who sees the dog sees the woman ."        :relative-subject  :a)
    ("the girl who eats a pie sees the dog ."           :relative-subject  :a)
    ("who eats a pie ?"                                 :wh-question       :a)
    ("what does Sue eat ?"                              :wh-question       :a)
    ("does Bob eat a hamburger ?"                       :yes-no-question   :a)
    ("eat the pie ."                                    :imperative        :a)
    ("give Sue a book ."                                :imperative        :a)
    ("the dog , Fido sees the man ."                    :apposition        :a)
    ("the boy , Bob eats a pie ."                       :apposition        :a)
    ("Sue eats two pies ."                              :number            :a)
    ("every boy eats a pie ."                           :quantifier        :a)
    ("Bob attends a party ."                            :transitive        :a)

    ;; ---------------- band B: stretch ----------------
    ;; words PARSIFAL knows and the ontology does not
    ("the cat sees the dog ."                           :transitive        :b :ontology-type)
    ("Sue meets Bob ."                                  :transitive        :b :ontology-type)
    ("Bob hits the ball ."                              :transitive        :b :ontology-type)
    ("the friend eats a pie ."                          :transitive        :b :ontology-type)
    ("Sue drives the car ."                             :transitive        :b :ontology-type)
    ("the elephant eats bread ."                        :transitive        :b :ontology-type)
    ("Sue believes that Bob eats a pie ."               :complement        :b :ontology-type)
    ("Bob invites Sue ."                                :transitive        :b :ontology-type)
    ;; words neither side knows
    ("Sue bakes a pie ."                                :transitive        :b :lexicon)
    ("the chef eats soup ."                             :transitive        :b :lexicon)
    ("Sue enjoys dinner ."                              :transitive        :b :lexicon)
    ("Bob repairs the automobile ."                     :transitive        :b :lexicon)
    ;; constructions, every word in the band-A vocabulary
    ("Sue eats a pie and Bob eats a hamburger ."        :coordination      :b :grammar)
    ("the boy and the girl eat a pie ."                 :coordination-np   :b :grammar)
    ("Sue does not eat a pie ."                         :negation          :b :grammar)
    ("Sue wants to eat a pie ."                         :control           :b :grammar)
    ("Bob sees the boy that Sue knows ."                :relative-object   :b :grammar)
    ("the boy that Sue sees eats a hamburger ."         :relative-object   :b :grammar)
    ("Sue eats a pie in the kitchen on Monday ."        :two-adjuncts      :b :grammar)
    ("Sue eats the pie quickly in the kitchen ."        :adverb-plus-pp    :b :grammar)
    ("there is a dog in the kitchen ."                  :existential       :b :grammar)
    ("Sue ate a pie yesterday ."                        :past-tense        :b :grammar)
    ("the pie that Sue eats is red ."                   :predicate-adj     :b :grammar)
    ;; type-legal but semantically odd -- does the lattice catch it?
    ("the dog eats a dollar ."                          :odd-but-typed     :b :extracted)
    ("Sue eats a rock ."                                :odd-but-typed     :b :extracted))
  "(SENTENCE CONSTRUCTION BAND [EXPECTED-LAYER]). EXPECTED-LAYER is only set on
   band :B rows; :EXTRACTED means \"I expect this one to get in\".")

;;; --- Classification --------------------------------------------------------
;;; cg-from-parse signals plain ERRORs with message strings, not condition
;;; classes, so the layer has to be read off the message. Every pattern below is
;;; anchored on text from a known call site; anything else lands in
;;; :UNCLASSIFIED rather than being guessed at, because a silent misfile is
;;; exactly the failure this file exists to avoid.

(defun survey-first-line (string)
  (let ((nl (position #\Newline string)))
    (if nl (subseq string 0 nl) string)))

(defun survey-unknown-words (sentence)
  "Tokens of SENTENCE that PARSIFAL's morphology cannot read -- i.e. a lexicon
gap. Uses the same MORPHO call the parser makes (driver.lisp LEXICAL-SCAN)."
  (handler-case
      (handler-bind ((warning #'muffle-warning))
        (mapcar #'first (remove-if #'second (lexical-scan sentence))))
    (error () nil)))

(defun classify-failure (sentence message)
  "Which layer refused SENTENCE, given the error MESSAGE it died with."
  (flet ((has (needle) (search needle message :test #'char-equal)))
    (cond
      ;; parse failure -- split it, which is the whole reason this file exists
      ((or (has "could not parse") (has "no parse to extract from"))
       (if (survey-unknown-words sentence) :lexicon :grammar))
      ;; the ontology has no type for a word the parser read fine
      ((has "no concept type for lemma") :ontology-type)
      ;; the lattice refused an arc: the type system working, not a defect
      ((or (has "is not consistent with") (has "out-arc type of the")) :ontology-contract)
      ((has "Unknown ontology profile") :ontology-type)
      (t :unclassified))))

(defparameter *survey-layers*
  '(:extracted :lexicon :grammar :ontology-type :ontology-contract :extractor :unclassified))

(defparameter *survey-layer-labels*
  '((:extracted         . "extracted")
    (:lexicon           . "lexicon gap       (add a dict entry)")
    (:grammar           . "GRAMMAR gap       (real parser work)")
    (:ontology-type     . "ontology: no type (add a concept type)")
    (:ontology-contract . "ontology: CONTRACT refusal (correct)")
    (:extractor         . "extractor         (our bug)")
    (:unclassified      . "unclassified")))

;;; --- The run ---------------------------------------------------------------

(defun survey-ingest (&key (corpus *survey-corpus*))
  "Run every sentence and label it with the layer that took it or turned it
away. Returns a list of (SENTENCE CONSTRUCTION BAND EXPECTED LAYER DETAIL GRAPH)."
  (mapcar
   (lambda (row)
     (destructuring-bind (sentence construction band &optional expected) row
       (handler-case
           (handler-bind ((warning #'muffle-warning))
             (let ((graph (parse-and-extract sentence :on-missing :error)))
               (list sentence construction band expected :extracted nil graph)))
         (error (e)
           (let* ((msg   (princ-to-string e))
                  (layer (classify-failure sentence msg)))
             (list sentence construction band expected layer
                   (survey-first-line msg) nil))))))
   corpus))

(defun survey-tally (rows)
  "ALIST of (LAYER . COUNT) over ROWS, in *survey-layers* order."
  (mapcar (lambda (layer)
            (cons layer (count layer rows :key #'fifth)))
          *survey-layers*))

(defun survey-report-band (rows band stream)
  (let* ((in    (remove band rows :key #'third :test-not #'eq))
         (n     (length in))
         (tally (survey-tally in)))
    (format stream "~&~%--- band ~a: ~d sentence~:p ---~%" band n)
    (dolist (cell tally)
      (when (plusp (cdr cell))
        (format stream "  ~38a ~3d   ~5,1f%~%"
                (cdr (assoc (car cell) *survey-layer-labels*))
                (cdr cell)
                (* 100.0 (/ (cdr cell) n)))))
    in))

(defun survey-report-failures (rows stream)
  (let ((bad (remove :extracted rows :key #'fifth)))
    (when bad
      (format stream "~&~%--- every sentence that did not get in ---~%")
      (dolist (layer (rest *survey-layers*))
        (let ((group (remove layer bad :key #'fifth :test-not #'eq)))
          (when group
            (format stream "~%  ~a~%" (cdr (assoc layer *survey-layer-labels*)))
            (dolist (r group)
              (format stream "    [~a/~a] ~s~%" (third r) (second r) (first r))
              (when (sixth r)
                (format stream "        ~a~%" (sixth r))))))))))

(defun survey-report-predictions (rows stream)
  "Band B only: where the prediction was wrong, which is the interesting part."
  (let ((b (remove :b rows :key #'third :test-not #'eq)))
    (format stream "~&~%--- band B: predicted vs. actual ---~%")
    (let ((hits (count-if (lambda (r) (eq (fourth r) (fifth r))) b)))
      (format stream "  ~d of ~d predictions correct~%" hits (length b))
      (dolist (r b)
        (unless (eq (fourth r) (fifth r))
          (format stream "    expected ~a, got ~a  --  ~s~%"
                  (fourth r) (fifth r) (first r)))))))

(defun survey-report-identity (rows &key (name "Sue") (stream *standard-output*))
  "The secondary number, carried over from multi-sentence-kb.lisp: does the store
know NAME is one person? Measured on the UNJOINED graphs -- graph maintenance is
destructive by design, so anything measured after a join measures the join."
  (let ((ids '()) (mentions 0))
    (dolist (row rows)
      (let ((graph (seventh row)))
        (when graph
          (dolist (node (cg::nodes graph))
            (when (and (typep node 'cg::concept)
                       (equal (ignore-errors (cg::referent-name node)) name))
              (incf mentions)
              (let ((id (ignore-errors (cg::id (cg::content (cg::referent node))))))
                (when id (push id ids))))))))
    (format stream "~&~%--- identity (unjoined) ---~%")
    (format stream "  ~s: ~d mention~:p, ~d distinct individual id~:p~%"
            name mentions (length (remove-duplicates ids :test #'equal)))))

(defun run-intake-survey (&key (corpus *survey-corpus*) (stream *standard-output*))
  (ensure-cgraph) (ensure-domain-lexicon) (ensure-grammar)
  (format stream "~&~%############ intake survey ############~%")
  (let ((rows (survey-ingest :corpus corpus)))
    (format stream "~&~%=== WHICH LAYER REFUSED IT ===~%")
    (survey-report-band rows :a stream)
    (survey-report-band rows :b stream)
    (survey-report-failures rows stream)
    (survey-report-predictions rows stream)
    (survey-report-identity rows :stream stream)
    (format stream "~%############ end ############~%")
    rows))

(run-intake-survey)
