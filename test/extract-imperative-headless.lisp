;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live imperative check: "see the dog ."
;;; PARSIFAL inserts the implicit 2nd-person subject, so the agent arrives as the
;;; pronoun "you"; the extractor realizes it as an indexical individual
;;; [PERSON: You]:
;;;   [SEE]-(agnt)->[PERSON: You] (obj)->[DOG: #].
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-imperative-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun extract-imperative-headless-test
    (&optional (sentence "see the dog .") (verbose t))
  (let ((ok (pa::parse-sentence sentence
                                :initial-rule (intern "INITIAL-RULE" :parsifal))))
    (cond
      ((not ok)
       (format t "~&extract-imperative-headless-test: parse FAILED for ~s <<<~%" sentence)
       nil)
      (t
       ;; see/dog/person all in test-types -> strict :error.
       (let* ((graph (ir->cgraph (parse->ir pa::c)))
              (text  (ignore-errors (cg::format-cgraph graph)))
              (up    (and (stringp text) (string-upcase text)))
              (pass  (and graph up
                          (search "SEE" up) (search "DOG" up)
                          (search "AGNT" up) (search "OBJ" up)
                          (search "PERSON" up)        ; implicit subject type
                          (search "YOU" up))))        ; ...realized as "you"
         (when verbose (format t "~&sentence: ~a~%graph:~%~a~%" sentence text))
         (format t "~&extract-imperative-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
         pass)))))

(extract-imperative-headless-test)
