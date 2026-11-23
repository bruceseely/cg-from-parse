;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; TELL and ASK: statements into a knowledge base, questions answered from it.
;;;
;;;   (tell "Dave drove a car from Maryland to Miami.")
;;;   (ask  "Did Dave drive a car?")        => T
;;;   (ask  "Did Greg drive a car?")        => NIL
;;;   (ask  "Who drove a car?")             => ("[PERSON: Dave]")
;;;
;;; A question's graph is a QUERY PATTERN (EXTRACT-GRAPH leaves its events
;;; generic), and asking is cgraph's QUERY -- projection of the pattern into
;;; each graph of the KB. A yes/no question is true when it projects somewhere:
;;; it asks whether that proposition holds, and the pattern IS the proposition.
;;; A wh-question's answer is what its query variable binds to.
;;;
;;; Projection is exactly as strict as the graphs, which is the point:
;;;   - "Greg believes Sue drove a car" does not make "did Sue drive a car ?"
;;;     true: the driving is inside Greg's belief, not asserted.
;;;   - "Dave drove from Maryland" does not make "did Dave drive TO Maryland ?"
;;;     true: (src) is not (dest).
;;; One thing projection does NOT compare is tense, which lives on the concept
;;; outside the referent -- so ASK checks the predicate's tense itself: "does
;;; Dave drive a car ?" is not answered by "Dave drove a car".
;;;
;;; The KB is a cgraph context, one per cgraph environment (like the name
;;; registry in identity.lisp, and for the same reason). TELL adds graphs with
;;; ADD-CGRAPH -- nothing is joined; whether ingest should join is still an open
;;; policy question (see notes/next-steps.md). Pass :KB to use a context of
;;; your own.

(in-package :cg-from-parse)

(defvar *kbs* (make-hash-table :test 'eq)
  "cgraph environment -> the context TELL adds to and ASK queries.")

(defun kb ()
  "The current environment's knowledge base (a cgraph context), made on first use."
  (ensure-cgraph)
  (or (gethash cg:*environment* *kbs*)
      (setf (gethash cg:*environment* *kbs*) (cg::make-context))))

(defun reset-kb ()
  "Forget everything TOLD in the current environment. Names stay known (see
RESET-NAME-REGISTRY to forget those too)."
  (remhash cg:*environment* *kbs*)
  nil)

(defun tell (sentence &key (kb (kb)) (on-missing :create))
  "Add SENTENCE's graph to KB (the current environment's, by default) and return
it. A question is refused: its graph is a pattern, and stored it would answer
itself."
  (multiple-value-bind (graph mood) (parse-and-extract sentence :on-missing on-missing)
    (when (question-mood-p mood)
      (error "cg-from-parse: ~s is a question -- ASK it; only statements can be told." sentence))
    (cg::add-cgraph graph kb)
    graph))

(defun ask (sentence &key (kb (kb)) (on-missing :create))
  "Answer SENTENCE from KB (the current environment's, by default).

  yes/no question  T when it holds in KB, else NIL.
  wh-question      the distinct answers, each a formatted concept
                   (\"[PERSON: Dave]\"), or NIL when there are none.
  statement        treated as \"is it true that ...?\": T or NIL.

The second value is the matching KB graphs (their head concepts), so an
answer can be said back: (mapcar #'say-graph ...) on their graphs, or cgraph's
SAY-QUERY-RESULTS on the raw results."
  (multiple-value-bind (pattern mood)
      ;; A question is a pattern already; a statement ASKed must be one too, or
      ;; [DRIVE: #12] would match only itself -- and asking must not add to the
      ;; discourse (discourse.lisp).
      (let ((*extract-as-pattern* t))
        (parse-and-extract sentence :on-missing on-missing))
    (when (eq mood :imperative)
      (error "cg-from-parse: ~s is a command -- there is nothing to look up." sentence))
    (let* ((head    (cg::head pattern))
           (results (remove-if-not (lambda (r) (tense-agrees-p head (getf r :graph)))
                                   (let ((*package* (find-package :conceptual-graphs)))
                                     (cg::query head kb))))
           (matched (remove-duplicates (mapcar (lambda (r) (getf r :graph)) results))))
      (values (if (eq mood :wh)
                  (remove-duplicates
                   (loop for r in results
                         append (loop for (nil . concept) in (getf r :bindings)
                                      collect (cg::format-node concept)))
                   :test #'string=)
                  (and results t))
              matched))))

(defun tense-agrees-p (pattern-head target-head)
  "False only when both heads carry a tense and the tenses differ. Projection
does not look at tense (it is not part of the referent), so without this
\"does Dave drive a car ?\" would be answered by \"Dave drove a car\". A
question with no tense, or a fact recorded without one, is not held against."
  (let ((want (ignore-errors (cg::concept-tense pattern-head)))
        (have (ignore-errors (cg::concept-tense target-head))))
    (or (null want) (null have) (eq want have))))
