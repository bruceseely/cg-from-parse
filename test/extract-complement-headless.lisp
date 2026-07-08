;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live complement-wrapper check (#7): a clausal complement is wrapped by a
;;; concept type chosen from its clause FORM (the parse's INF-S vs THAT-S feature,
;;; read by clause-complement-form):
;;;   a THAT-clause  is a statement  -> [PROPOSITION: <inner graph>]
;;;   an INFINITIVAL is an event     -> [SITUATION:    <inner graph>]
;;; So the same embedding machinery yields two different wrappers:
;;;   "the man knows that the boy sees the dog ." ->
;;;       [KNOW]-(expr)->[MAN: #] (stat)->[PROPOSITION:[SEE]...]
;;;   "the boy wants to go ." ->
;;;       [WANT]-(agnt)->[BOY: #] (prop)->[SITUATION:[GO]->(agnt)->[BOY]]
;;; The generic `prop' relation accepts either wrapper (dest ⊤); the stative
;;; `stat' is used only for a PROPOSITION (its dest is PROPOSITION). See
;;; notes/next-steps.md #7 (and #6 for the relation/role choice).
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-complement-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun %complement-text (sentence)
  "Parse SENTENCE and return its formatted CG (upcased, spaces removed), or NIL."
  (when (pa::parse-sentence sentence
                            :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let ((*on-missing-type* :create))   ; want/go aren't in test-types; know is
      (handler-bind ((warning #'muffle-warning))
        (let ((text (ignore-errors (cg::format-cgraph (ir->cgraph (parse->ir pa::c))))))
          (and (stringp text) (remove #\Space (string-upcase text))))))))

(defun extract-complement-headless-test (&optional (verbose t))
  (let* ((that (%complement-text "the man knows that the boy sees the dog ."))
         (inf  (%complement-text "the boy wants to go ."))
         (pass (and that inf
                    ;; that-clause -> PROPOSITION (statement), never SITUATION
                    (search "(STAT)→[PROPOSITION:[SEE" that)
                    (not (search "SITUATION" that))
                    ;; infinitival -> SITUATION (event), never PROPOSITION
                    (search "(PROP)→[SITUATION:[GO" inf)
                    (not (search "PROPOSITION" inf)))))
    (when verbose
      (format t "~&that-clause : ~a~%infinitival: ~a~%" that inf))
    (format t "~&extract-complement-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
    pass))

(extract-complement-headless-test)
