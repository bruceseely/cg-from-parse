;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live modifier check: adjective modifier "the big dog sees the man ."
;;; An adjective attaches to its NP as a surface `adj' daughter; the reader
;;; collects it (:adjs) and the emitter adds [NOUN]->(attr)->[ADJ]:
;;;   [SEE]-(agnt)->[DOG]->(attr)->[BIG] (obj)->[MAN].
;;; `big' isn't in test-types, so this runs with *on-missing-type* :create
;;; (BIG is created under ATTRIBUTE, the attr relation's dest).
;;;
;;; NB on PP adjuncts: PARSIFAL DROPS a verb-unlicensed PP ("... in the park")
;;; entirely -- it's in neither the case frame nor the surface tree -- and a
;;; licensed PP is already a case (give's to->dat). So PP adjuncts yield no
;;; extra extractable content here; adjective modifiers do. See notes/next-steps.md.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-modifier-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::reset-rule-table)
(pa::register-grammar pa::*np-rules* pa::*clause-rules* pa::*vp-np-rule*
                      pa::*pronoun-rule*)

(defun extract-modifier-headless-test
    (&optional (sentence "the big dog sees the man .") (verbose t))
  (let ((ok (pa::parse-sentence sentence
                                :initial-rule (intern "INITIAL-RULE" :parsifal))))
    (cond
      ((not ok)
       (format t "~&extract-modifier-headless-test: parse FAILED for ~s <<<~%" sentence)
       nil)
      (t
       (let* ((*on-missing-type* :create)   ; `big' isn't in test-types
              (graph (handler-bind ((warning #'muffle-warning))
                       (ir->cgraph (parse->ir pa::c))))
              (text  (ignore-errors (cg::format-cgraph graph)))
              (up    (and (stringp text) (string-upcase text)))
              (pass  (and graph up
                          (search "SEE"  up) (search "DOG" up) (search "MAN" up)
                          (search "AGNT" up) (search "OBJ" up)
                          (search "BIG"  up) (search "ATTR" up)))) ; adjective modifier
         (when verbose (format t "~&sentence: ~a~%graph:~%~a~%" sentence text))
         (format t "~&extract-modifier-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
         pass)))))

(extract-modifier-headless-test)
