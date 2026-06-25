;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live coreference check: object control "the boy persuaded the girl to go ."
;;; The embedded GO's subject is a trace bound to the matrix object (the girl),
;;; so the extracted graph must share ONE concept for the girl, reached from
;;; both PERSUADE's recipient arc and GO's agent arc.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-coref-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "test/integration/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::reset-rule-table)
(pa::register-grammar pa::*np-rules* pa::*clause-rules* pa::*inf-complement-rules*
                      pa::*delta-complement-rules* pa::*two-object-inf-rules*
                      pa::*vp-np-full-rule*)

(defun count-substr (needle haystack)
  (loop with n = 0 with start = 0
        for pos = (search needle haystack :start2 start)
        while pos do (incf n) (setf start (+ pos (length needle)))
        finally (return n)))

(defun extract-coref-headless-test (&optional (sentence "the boy persuaded the girl to go .")
                                              (verbose t))
  (let ((ok (pa::parse-sentence sentence
                                :initial-rule (intern "INITIAL-RULE" :parsifal))))
    (cond
      ((not ok)
       (format t "~&extract-coref-headless-test: parse FAILED for ~s <<<~%" sentence)
       nil)
      (t
       (let* ((*on-missing-type* :create)
              (ir    (parse->ir pa::c))
              ;; the clausal-complement arc is intentionally skipped (warns)
              (graph (handler-bind ((warning #'muffle-warning)) (ir->cgraph ir)))
              (text  (and graph (ignore-errors (cg::format-cgraph graph))))
              (up    (and (stringp text) (string-upcase text)))
              ;; Coreference signature: the controlled "girl" is ONE shared node
              ;; (reached from PERSUADE's rcpt and GO's agnt), so [GIRL] appears
              ;; exactly once -- not duplicated into two separate concepts.
              (girl-nodes (and up (count-substr "[GIRL" up)))
              (pass (and graph up
                         (search "PERSUADE" up) (search "BOY" up)
                         (search "GIRL" up)     (search "GO" up)
                         (search "AGNT" up)     (search "RCPT" up)
                         (eql girl-nodes 1))))
         (when verbose
           (format t "~&sentence:   ~a~%" sentence)
           (format t "~&IR:         ~s~%" ir)
           (format t "~&graph:~%~a~%" text)
           (format t "~&girl nodes: ~a (1 = coreferent/shared)~%" girl-nodes))
         (format t "~&extract-coref-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
         pass)))))

(extract-coref-headless-test)
