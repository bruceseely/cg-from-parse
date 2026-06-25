;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live ditransitive check: double-object "the man gives the woman the dog ."
;;; give fills three thematic cases -- AGT (subj), DAT (1st object = recipient),
;;; NEUT (2nd object = theme) -- which map to agnt / rcpt / obj. All of
;;; give/man/woman/dog are in test-types, so this runs under strict :error.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-ditransitive-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "test/integration/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::reset-rule-table)
(pa::register-grammar pa::*np-rules* pa::*clause-rules* pa::*vp-np-rule*)

(defun extract-ditransitive-headless-test
    (&optional (sentence "the man gives the woman the dog .") (verbose t))
  (let ((ok (pa::parse-sentence sentence
                                :initial-rule (intern "INITIAL-RULE" :parsifal))))
    (cond
      ((not ok)
       (format t "~&extract-ditransitive-headless-test: parse FAILED for ~s <<<~%" sentence)
       nil)
      (t
       (let* ((ir    (parse->ir pa::c))
              (graph (ir->cgraph ir))
              (text  (ignore-errors (cg::format-cgraph graph)))
              (up    (and (stringp text) (string-upcase text)))
              (pass  (and graph (typep graph 'cg::graph) up
                          (search "GIVE" up)
                          (search "AGNT" up) (search "MAN"   up)   ; agent
                          (search "RCPT" up) (search "WOMAN" up)   ; recipient
                          (search "OBJ"  up) (search "DOG"   up)))) ; theme
         (when verbose
           (format t "~&sentence: ~a~%" sentence)
           (format t "~&graph:~%~a~%" text))
         (format t "~&extract-ditransitive-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
         pass)))))

(extract-ditransitive-headless-test)
