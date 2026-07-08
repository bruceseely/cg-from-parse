;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live relative-clause check (subject relative on the matrix subject):
;;; "the boy who sees the dog sees the woman ."
;;; The relative clause "who sees the dog" lives in the head noun's case-frame
;;; `mods'; its subject (the bound relative pronoun `who') corefers with the
;;; head BOY. Same context, so BOY is ONE shared node: agent of the matrix
;;; "sees the woman" AND of the relative "sees the dog".
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-relative-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::reset-rule-table)
(pa::register-grammar pa::*np-rules* pa::*clause-rules* pa::*vp-np-rule*
                      pa::*pronoun-rule* pa::*inf-complement-rules*
                      pa::*wh-question-rules* pa::*relative-clause-rules*)

(defun count-substr (needle haystack)
  (loop with n = 0 with start = 0
        for pos = (search needle haystack :start2 start)
        while pos do (incf n) (setf start (+ pos (length needle)))
        finally (return n)))

(defun extract-relative-headless-test
    (&optional (sentence "the boy who sees the dog sees the woman .") (verbose t))
  (let ((ok (pa::parse-sentence sentence
                                :initial-rule (intern "INITIAL-RULE" :parsifal))))
    (cond
      ((not ok)
       (format t "~&extract-relative-headless-test: parse FAILED for ~s <<<~%" sentence)
       nil)
      (t
       (let* ((graph (ir->cgraph (parse->ir pa::c)))
              (text  (ignore-errors (cg::format-cgraph graph)))
              (up    (and (stringp text) (string-upcase text)))
              (see-preds (and up (count-substr "[SEE" up)))   ; matrix + relative
              (boy-nodes (and up (count-substr "[BOY" up)))   ; shared head -> 1
              (pass  (and graph up
                          (search "WOMAN" up) (search "DOG" up)
                          (search "AGNT" up)  (search "OBJ" up)
                          (eql see-preds 2)     ; two seeings
                          (eql boy-nodes 1))))  ; boy shared across both
         (when verbose
           (format t "~&sentence: ~a~%graph:~%~a~%" sentence text)
           (format t "~&see-preds: ~a  boy-nodes: ~a (2 seeings / 1 shared boy)~%"
                   see-preds boy-nodes))
         (format t "~&extract-relative-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
         pass)))))

(extract-relative-headless-test)
