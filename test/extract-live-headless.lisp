;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live end-to-end check: PARSIFAL parse  ->  parse->ir  ->  ir->cgraph.
;;; Exercises the WHOLE pipeline, including the reader half against a real
;;; parse. Run with:
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' \
;;;     --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-live-headless.lisp
;;;
;;; "the man sees the dog ." -> SEE with agt=MAN (subj), neut=DOG (obj).
;;; man/dog are in test-types; `see' is not (test-types is a controlled catalog,
;;; not the user's full ontology), so this runs with *on-missing-type* :create:
;;; man/dog resolve, SEE is created under ACT -- the realistic out-of-ontology
;;; case, exercising the whole reader + emitter against a live parse.

(in-package :cg-from-parse)

;; 1. cgraph TEST-TYPES catalog, brought up non-destructively.
(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

;; 2. PARSIFAL grammar: load the clause-grammar rule groups and register the
;;    minimal transitive set (mirrors gram1-caseframe-test).
(load (merge-pathnames "test/integration/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::reset-rule-table)
(pa::register-grammar pa::*np-rules* pa::*clause-rules* pa::*vp-np-rule*)

(defun extract-live-headless-test (&optional (sentence "the man sees the dog .")
                                             (verbose t))
  (let ((ok (pa::parse-sentence sentence
                                :initial-rule (intern "INITIAL-RULE" :parsifal))))
    (cond
      ((not ok)
       (format t "~&extract-live-headless-test: parse FAILED for ~s <<<~%" sentence)
       nil)
      (t
       (let* ((*on-missing-type* :create)   ; man/dog in test-types; SEE created under ACT
              (ir    (parse->ir pa::c))
              (graph (ir->cgraph ir))
              (text  (ignore-errors (cg::format-cgraph graph)))
              (up    (and (stringp text) (string-upcase text)))
              (pass  (and graph (typep graph 'cg::graph) up
                          (search "SEE"  up) (search "AGNT" up)
                          (search "MAN"  up) (search "OBJ"  up)
                          (search "DOG"  up))))
         (when verbose
           (format t "~&sentence: ~a~%" sentence)
           (format t "~&IR:       ~s~%" ir)
           (format t "~&graph:~%~a~%" text))
         (format t "~&extract-live-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
         pass)))))

(extract-live-headless-test)
