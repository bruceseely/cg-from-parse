;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live wh-question check:
;;;   "who sees the dog ?"      -> [SEE]-(agnt)->[PERSON: *x] (obj)->[DOG: #]
;;;   "what does the dog see ?" -> [SEE]-(agnt)->[DOG: #] (obj)->[ENTITY: *x]
;;; A wh-interrogative (subject "who" in place, or a fronted "what" leaving a
;;; trace) is the QUERIED element: a concept of the wh-type (who->person,
;;; what->entity) carrying a query variable (*x) -- so the extracted graph is a
;;; runnable query pattern for cgraph's query engine. The lone *x isn't shown by
;;; the formatter, so we check the variable on the concept (node-variable).
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-question-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "test/integration/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun queried-concept (graph)
  "The concept carrying a query variable -- the wh-element."
  (find-if (lambda (n) (and (typep n 'cg::concept) (cg::node-variable n)))
           (cg::collect-nodes (cg::head graph))))

(defun question-info (sentence)
  "Return (values queried-type-string has-variable-p) for SENTENCE's wh-element."
  (when (pa::parse-sentence sentence :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let* ((graph (ir->cgraph (parse->ir pa::c)))
           (q     (queried-concept graph)))
      (values (and q (string (cg::label (cg::concept-type q))))
              (and q (cg::node-variable q) t)))))

(defun extract-question-headless-test (&optional (verbose t))
  (multiple-value-bind (who-type who-var) (question-info "who sees the dog ?")
    (multiple-value-bind (what-type what-var) (question-info "what does the dog see ?")
      (let ((pass (and (equal who-type "PERSON")  who-var     ; who -> queried person
                       (equal what-type "ENTITY") what-var))) ; what -> queried entity
        (when verbose
          (format t "~&who  sees the dog ? -> queried [~a], var=~s~%" who-type who-var)
          (format t "~&what does the dog see ? -> queried [~a], var=~s~%" what-type what-var))
        (format t "~&extract-question-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
        pass))))

(extract-question-headless-test)
