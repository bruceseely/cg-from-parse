;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; driver.lisp -- one-call ergonomics: string -> conceptual graph.
;;;
;;; parse-and-extract hides the boilerplate (load + register PARSIFAL's full
;;; grammar, parse-sentence with the initial rule, then extract-graph) so a
;;; caller can go straight from English to a cgraph graph. The grammar is
;;; loaded/registered once per session and cached.
;;;
;;; It self-initializes both cgraph (the type catalog + *context*) and the
;;; PARSIFAL grammar on first use, each a no-op if already set up -- so it works
;;; right after (ql:quickload :cg-from-parse) without disturbing a running session.

(in-package :cg-from-parse)

(defvar *grammar-loaded* nil
  "T once PARSIFAL's full grammar has been loaded + registered this session.")

(defun cgraph-ready-p ()
  "True when cgraph is initialized: the type catalog is loaded (top type bound)
and a *context* exists."
  (and (boundp 'cg::*concept-type-top*)
       cg::*concept-type-top*
       cg::*context*))

(defun ensure-cgraph ()
  "Make sure cgraph is initialized -- type catalog loaded from the user's
~/.cgraph/types and *context* bound. No-op if already initialized, so a running
session isn't disturbed. (*package* must be :cg while loading: cgraph's type
loaders use plain READ.)"
  (unless (cgraph-ready-p)
    (let ((*package* (find-package :conceptual-graphs)))
      (cg::setup-cgraph (asdf:system-source-directory :cgraph))
      (cg::reset-cgraph)))
  t)

(defun ensure-grammar (&optional force)
  "Load and register PARSIFAL's full grammar so parse-sentence can handle any
supported construction. Done once per session (pass FORCE to redo). The grammar
lives in parsifal's system/grammar/clause-grammar.lisp; load-full-grammar
there composes and registers it."
  (when (or force (not *grammar-loaded*))
    (load (asdf:system-relative-pathname :parsifal
                                         "system/grammar/clause-grammar.lisp"))
    (funcall (intern "LOAD-FULL-GRAMMAR" :parsifal))
    (setf *grammar-loaded* t))
  t)

;;; ===========================================================
;;; Diagnosing a failed parse
;;; ===========================================================
;;;
;;; PARSIFAL is wait-and-see with NO backtracking: when no rule in the active
;;; packets matches the look-ahead buffer, parse-loop warns "No rule applies."
;;; and returns NIL. That bare NIL was all parse-and-extract had to report --
;;; "could not parse", with no hint whether the sentence tripped on a word the
;;; lexicon lacks, a construction the grammar has no rule for, or a wrong turn
;;; taken several rules earlier.
;;;
;;; Everything needed is still sitting in the parser's globals when the loop
;;; gives up: the buffer (the node nothing matched), the unconsumed *wstring*,
;;; the active packets, the derivation (*deriv* -- every rule that DID fire),
;;; and the partial tree hanging off c. PARSE-FAILURE-REPORT reads that state
;;; out; parse-and-extract now signals it along with the error, and
;;; DIAGNOSE-PARSE is the REPL entry point ("why won't this parse?").
;;;
;;; The state is only valid AT the dead end -- any further parse overwrites it --
;;; so the report is built before anything else runs.

(defun lexical-scan (sentence)
  "How PARSIFAL's morphology reads each token of SENTENCE: a list of
(SURFACE ROOT FEATURES) per token, ROOT and FEATURES NIL for a token the lexicon
does not have. Same MORPHO call read-sentence makes, so this is exactly what the
parser saw -- including the inflection stripping that maps a surface form to its
entry (`eating' -> EAT with ING PART ADJ replacing the tensed features)."
  (mapcar (lambda (tok)
            (if (pa::morpho (reverse (map 'list #'char-code tok)))
                (let ((w pa::*wrd*))
                  (list tok (pa::root-of w) (get w 'pa::features)))
                (list tok nil nil)))
          (pa::tokenize sentence)))

(defun node-brief (node)
  "One-line label for a PARSIFAL node: its word (a leaf) or node type (a phrase),
followed by its feature list."
  (if (null node)
      "<none>"
      (format nil "~(~a~)  [~(~{~a~^ ~}~)]"
              (or (pa::getr 'pa::word node) (car node))
              (pa::fe node))))

(defun outermost-node (node)
  "Walk up from NODE to the top of the tree it hangs in (the partial parse)."
  (let ((n node))
    (loop for up = (and n (ignore-errors (pa::father-node n)))
          while up do (setf n up))
    n))

(defun packet-rules (packet)
  "The NORMAL rules registered in PACKET, as a sorted list of (NAME . INDEX-FEATURE)
-- what the grammar could have done at a dead end with PACKET active. INDEX-FEATURE
is the feature the rule is indexed under (NOINDEXF = tested against any node);
a rule whose index feature the stalled node lacks is never even tested."
  (let ((rules '()))
    (maphash (lambda (key items)
               (destructuring-bind (indexf type pkt) key
                 (when (and (eq pkt packet) (eq type 'pa::normal))
                   (dolist (item items) (push (cons (third item) indexf) rules)))))
             pa::*rule-index*)
    (sort (remove-duplicates rules :key #'car)
          #'string< :key (lambda (r) (symbol-name (car r))))))

(defun parse-failure-report (sentence)
  "A report on the dead end the CURRENT parser state is sitting in, as a string:
how the lexicon read each word, which word the parse stalled on, what was already
built, which rules fired, and which rules could still have fired there. Call it
immediately after a failed pa:parse-sentence -- it reads live parser globals, and
a later parse overwrites them. Used by parse-and-extract's error; see
DIAGNOSE-PARSE for the REPL entry point."
  ;; Capture the parse state first: the lexical scan re-runs MORPHO.
  (let* ((stalled   (and (arrayp pa::*buffer*)
                         (aref pa::*buffer* pa::*bufpntr*)))
         (pending   (copy-list pa::*wstring*))
         (packets   (copy-list pa::*activepackets*))
         (deriv     (reverse pa::*deriv*))
         (current   pa::c)
         (top       (outermost-node (or current pa::s)))
         (candidates (ignore-errors
                      (mapcar #'third
                              (apply #'append
                                     (pa::fetchrules 'pa::normal pa::*bufpntr*)))))
         (sent      (copy-list pa::*sent*))
         ;; A leaf node carries its input position; a phrase node (an NP the
         ;; parser had already built and could not place) does not, so fall back
         ;; to the leftmost leaf it dominates.
         (pos       (and stalled
                         (or (ignore-errors (pa::getr 'pa::inputpos stalled))
                             (let ((p (ignore-errors (pa::node-min-pos stalled))))
                               (and p (<= p (length pa::*sent*)) p)))))
         (lex       (ignore-errors (lexical-scan sentence)))
         (unknown   (mapcar #'first (remove-if #'second lex))))
    (with-output-to-string (out)
      (format out "~&how the lexicon read it (surface -> root: features)~%")
      (loop for (surface root feats) in lex
            for i from 1
            do (format out "  ~2d. ~12a ~14a ~@[[~(~{~a~^ ~}~)]~]~@[~a~]~%"
                       i surface
                       (if root (format nil "-> ~(~a~)" root) "")
                       feats
                       (unless root "<-- NOT IN THE LEXICON")))
      (when unknown
        (format out "~%dropped ~r unknown word~:p: ~{~a~^ ~}~%~
                   ~2t read-sentence DROPS what the lexicon lacks, so the parse ran~%~
                   ~2t on a SHORTER sentence than you typed. Fix the spelling, or~%~
                   ~2t add the word~p to~%~
                   ~2t parsifal/system/core/runtime/supplement.dict -- paste-ready:~%~%"
                (length unknown) unknown (length unknown))
        ;; Emit a line the ontologist can paste as-is, carrying the sentence
        ;; that needed the word. Every other entry in supplement.dict records
        ;; WHY it is there; a bare `(jlike foo block)' added mid-task is how
        ;; that rationale gets lost, so supply the comment rather than asking
        ;; for it at the one moment nobody wants to stop and write prose.
        (dolist (w unknown)
          (format out "~6t(jlike ~(~a~) block)~vt; inanimate physobj count noun (~s)~%"
                  w (max 30 (+ 14 (length (string w)))) sentence))
        (format out "~%~2t `block' is the clone target -- pick one that fits:~%~
                     ~4t block  inanimate count thing      boy   human animate~%~
                     ~4t hair   mass noun (no determiner)  fido  proper name~%~
                     ~2t A verb or anything with a case frame needs `df', not~%~
                     ~2t `jlike'; see the header of supplement.dict.~%"))
      (format out "~%where it stalled~%")
      (format out "  no rule matched: ~a~@[   (word ~a~@[ of ~a~])~]~%"
              (node-brief stalled) pos (and pos (length sent)))
      (when (and pos sent (> pos 1))
        (format out "  consumed:    ~(~{~a~^ ~}~)~%"
                (subseq sent 0 (min (1- pos) (length sent)))))
      (when pending
        (format out "  still ahead: ~(~{~a~^ ~}~)~%"
                (mapcar (lambda (n) (or (pa::getr 'pa::word n) '?)) pending)))
      (format out "~%parser state at the dead end~%")
      (format out "  current node c : ~a~%" (node-brief current))
      (format out "  active packets : ~(~{~a~^ ~}~)~%" packets)
      (format out "  rules tested there: ~:[none~;~(~{~a~^ ~}~)~]~%"
              candidates candidates)
      (format out "  rules that fired (~a): ~(~{~a~^ > ~}~)~%" (length deriv) deriv)
      (format out "~%what the grammar could still have done (rules in the active packets)~%")
      (dolist (p packets)
        (let ((rules (packet-rules p)))
          (format out "  ~(~a~): ~:[--~;~:*~(~{~a~^ ~}~)~]~%"
                  p (mapcar (lambda (r)
                              (format nil "~a[~a]" (car r) (cdr r)))
                            rules))))
      (when top
        (format out "~%the partial tree it did build~%")
        (let ((tree (with-output-to-string (s) (ignore-errors (pa::stree top s)))))
          (dolist (line (uiop:split-string (string-right-trim '(#\Newline) tree)
                                           :separator '(#\Newline)))
            (format out "  ~a~%" line))))
      (format out "~%reading this report~%")
      (dolist (line '("* A word `NOT IN THE LEXICON' is the whole story -- fix that first."
                      "* Otherwise the stalled node is a constituent that no rule in the active"
                      "  packets accepts. `rules tested there' lists the rules whose index feature"
                      "  the node actually has; `none' means not one pattern was even tried --"
                      "  i.e. the grammar has no rule for this construction in these packets."
                      "* The rules that fired show the turn that led here. A wrong-but-legal rule"
                      "  strands the real constituent one step later: an aux that completes early"
                      "  (aux-complete rather than a progressive/copula rule) lets main-verb take"
                      "  the auxiliary as the verb, and the participle is then left with nothing."
                      "* Marcus's own grammar is the reference for a missing rule:"
                      "  parsifal/notes/from-marcus/gram1.l (also"
                      "  parsifal/notes/pidgin-grammar-rules-1977.text) -- grep either for the"
                      "  packet name above. What THIS port registers lives in"
                      "  parsifal/system/grammar/clause-grammar.lisp."))
        (format out "  ~a~%" line)))))

(defun diagnose-parse (sentence &key (stream *standard-output*) (tree t))
  "Parse SENTENCE and print WHY it failed -- the REPL answer to `why won't this
parse?'. Returns T if it parsed (printing its surface tree unless TREE is NIL),
NIL if it did not (printing PARSE-FAILURE-REPORT). Warnings are muffled: the
report covers what they would have said.

  (diagnose-parse \"the girl is eating pie in the kitchen .\")"
  (ensure-grammar)
  (let ((ok (handler-bind ((warning #'muffle-warning))
              (pa:parse-sentence sentence
                                 :initial-rule (intern "INITIAL-RULE" :parsifal)))))
    (cond ((not ok)
           (format stream "~&PARSE FAILED: ~s~%~%~a" sentence
                   (parse-failure-report sentence))
           nil)
          (t
           (format stream "~&parsed: ~s~%" sentence)
           (when tree
             (let ((top (outermost-node (or pa::c pa::s))))
               (when top (pa::stree top stream))))
           t))))

(defun parse-and-extract (sentence &key (on-missing *on-missing-type*))
  "Parse SENTENCE with PARSIFAL and return its conceptual graph (a cgraph graph).
Loads + registers the full grammar on first use. Signals an error if PARSIFAL
can't parse SENTENCE -- with PARSE-FAILURE-REPORT\'s account of where and why
(see DIAGNOSE-PARSE). ON-MISSING binds *on-missing-type* for out-of-ontology
lemmas (:error / :create / :top).

  (parse-and-extract \"the man gives the woman the book .\")
  (parse-and-extract \"the man sees the dog in the park .\" :on-missing :create)"
  (ensure-cgraph)
  (ensure-grammar)
  (let ((*on-missing-type* on-missing))
    (if (pa:parse-sentence sentence :initial-rule (intern "INITIAL-RULE" :parsifal))
        (extract-graph)
        (error "cg-from-parse: PARSIFAL could not parse ~s~2%~a~%~
                Re-run this report any time with ~
                (diagnose-parse ~s)."
               sentence (parse-failure-report sentence) sentence))))

(defun sentence->cg-text (sentence &key (on-missing *on-missing-type*))
  "Convenience: parse-and-extract SENTENCE and return the formatted CG string.
Routes through cg-text, so a promoted [EXCHANGE] graph gets the block renderer
(render.lisp) and everything else the engine's format-cgraph."
  (cg-text (parse-and-extract sentence :on-missing on-missing)))

(defun say-graph (graph)
  "Realize GRAPH back to English via cgraph's realizer (say), with cross-context
coreference generation enabled. cgraph's *anaphora-cross-coref* defaults to NIL, so
by default a coreferring occurrence in an embedded context (what the extractor emits
for a resolved pronoun or a control trace, [MAN:?x] bound to [MAN:*x]) would surface
as a fresh NP (\"a man\") instead of a pronoun. Binding it here keeps the round-trip
faithful to the coreference the extractor encoded (\"...the dog sees him\", not
\"...sees a man\") -- without changing cgraph's global default for other callers."
  (let ((cg::*anaphora-cross-coref* t))
    (cg::say graph)))

(defun sentence->say (sentence &key (on-missing *on-missing-type*))
  "Round-trip: parse SENTENCE, extract its conceptual graph, and realize that graph
back to English (coreference-aware -- see say-graph). English in -> graph -> English
out; the natural-language counterpart of sentence->cg-text.

  (sentence->say \"the man knows that the dog sees him .\")
  ;; => \"The man knows that the dog sees him.\""
  (say-graph (parse-and-extract sentence :on-missing on-missing)))

(defun browse-types (&key (port 8060))
  "Start cgraph's web concept-type browser on THIS session's live type catalog and
return the URL to open. Loads the cgraph-web and cgraph-editor systems
(Hunchentoot) on demand and
ensures cgraph is initialized first, so the browser shows exactly the ontology this
cg-from-parse session is using -- including any types created during extraction under
:create, since cgraph's type catalog is process-global and shared in this image.

Keep the REPL alive: the server runs inside this Lisp image and dies when it exits,
so starting it from a one-shot/non-interactive process is a common cause of a dead
page. Stop it with (cg::stop-web-server) (or restart on a new PORT).

IMPORTANT -- open http://127.0.0.1:<port>, NOT http://localhost:<port>. The server
binds IPv4 127.0.0.1, and `localhost' can resolve to IPv6 ::1 first (nothing listens
there), which shows as `Unable to connect' in the browser."
  (ensure-cgraph)
  (asdf:load-system :cgraph-web)
  ;; The browser page carries two buttons that call the editor -- "Draw…" on the
  ;; type form and "Editor" in the toolbar -- and those routes live in a system
  ;; of their own. Loading the page's server without them served a page whose
  ;; buttons answered "could not open the editor: 404".
  (asdf:load-system :cgraph-editor)
  (funcall (intern "START-WEB-SERVER" :cg) :port port)
  (let ((url (format nil "http://127.0.0.1:~a" port)))
    (format t "~&Concept-type browser ready: ~a~%~
                 (open that exact URL -- 127.0.0.1, not localhost; ~
                 stop with (cg::stop-web-server))~%" url)
    url))

(defun browse-lexicon (&key all (stream *standard-output*) (columns 6))
  "Print the words PARSIFAL can currently parse -- the live lexicon this session
is using -- and return the list of word-name strings (sorted). This is the lexicon
counterpart to BROWSE-TYPES: the lexicon (what words parse at all) and the concept-type
ontology (what a parsed lemma maps to) are independent catalogs, and a word can be in
one without the other -- e.g. `want' is in the lexicon but has no concept type. A REPL
lister rather than a web page; STREAM/COLUMNS control the printed layout.

By default the punctuation tokens and clitic fragments (`.', `'d', `'s', ...) that
are also lexicon entries are omitted, leaving the words one would add to a sentence;
pass ALL non-nil to include them and get the complete inventory.

  (browse-lexicon)             ; content words: prints the table, returns the list
  (browse-lexicon :all t)      ; everything, incl. punctuation + clitics
  (member \"want\" (browse-lexicon) :test #'string=)"
  (ensure-grammar)
  (let* ((words (mapcar (lambda (s) (string-downcase (symbol-name s)))
                        (pa:lexicon-words :sort t :all all)))
         (n (length words)))
    (format stream "~&Lexicon: ~a ~a  (add more in ~
                    parsifal/system/core/runtime/supplement.dict~
                    ~@[; content words only -- :all t for everything~])~%~%"
            n (if all "entries" "words") (not all))
    (loop for w in words
          for i from 1
          do (format stream "  ~va" 18 w)
             (when (zerop (mod i columns)) (terpri stream)))
    (unless (zerop (mod n columns)) (terpri stream))
    words))
