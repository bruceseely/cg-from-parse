;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live named-individual check: "mitch sees the dog ."
;;; A proper name ("mitch", a name NP marked hanim) becomes a named individual
;;; [PERSON: Mitch] -- the type from the name's semantic markers (hanim->person),
;;; the name as the individual's :name. (mitch is in PARSIFAL's dictionary.)
;;;   [SEE]-(agnt)->[PERSON: Mitch] (obj)->[DOG: #].
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-named-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "test/integration/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun extract-named-headless-test
    (&optional (sentence "mitch sees the dog .") (verbose t))
  (let ((ok (pa::parse-sentence sentence
                                :initial-rule (intern "INITIAL-RULE" :parsifal))))
    (cond
      ((not ok)
       (format t "~&extract-named-headless-test: parse FAILED for ~s <<<~%" sentence)
       nil)
      (t
       ;; see/person/dog are all in test-types -> strict :error.
       (let* ((graph (ir->cgraph (parse->ir pa::c)))
              (text  (ignore-errors (cg::format-cgraph graph)))
              (up    (and (stringp text) (string-upcase text)))
              (pass  (and graph up
                          (search "SEE"    up) (search "DOG" up)
                          (search "AGNT"   up) (search "OBJ" up)
                          (search "PERSON" up)        ; type from hanim marker
                          (search "MITCH"  up))))     ; the name as individual
         (when verbose (format t "~&sentence: ~a~%graph:~%~a~%" sentence text))
         (format t "~&extract-named-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
         pass)))))

(extract-named-headless-test)
