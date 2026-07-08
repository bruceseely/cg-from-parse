;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live raising check: "the boy seems to go ."
;;; `seem' is a raising verb: it takes ONLY the clausal complement (no agent of
;;; its own), and the surface subject "the boy" is semantically the agent of the
;;; embedded "go". PARSIFAL resolves this at the case level, so it falls out of
;;; the clausal-complement machinery with no new code. The complement is an
;;; INFINITIVAL ("to go"), so it wraps as a SITUATION (an event), not a
;;; PROPOSITION -- see #7 / complement-type-for:
;;;   [SEEM]->(prop)->[SITUATION:[GO]->(agnt)->[BOY: #]].
;;; (Contrast control "persuade", where the controller IS a matrix argument.)
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-raising-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun extract-raising-headless-test
    (&optional (sentence "the boy seems to go .") (verbose t))
  (let ((ok (pa::parse-sentence sentence
                                :initial-rule (intern "INITIAL-RULE" :parsifal))))
    (cond
      ((not ok)
       (format t "~&extract-raising-headless-test: parse FAILED for ~s <<<~%" sentence)
       nil)
      (t
       ;; seem/go aren't in test-types; the boy is. Use :create for the verbs.
       (let* ((*on-missing-type* :create)
              (graph (handler-bind ((warning #'muffle-warning))
                       (ir->cgraph (parse->ir pa::c))))
              (text  (ignore-errors (cg::format-cgraph graph)))
              (up    (and (stringp text) (string-upcase text)))
              (pass  (and graph up
                          (search "SEEM" up) (search "SITUATION" up)
                          (search "GO"  up)  (search "AGNT" up)
                          (search "BOY" up)
                          ;; the boy is the agent of GO inside the situation,
                          ;; not a direct argument of SEEM
                          (search "SITUATION:[GO" (remove #\Space up)))))
         (when verbose (format t "~&sentence: ~a~%graph:~%~a~%" sentence text))
         (format t "~&extract-raising-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
         pass)))))

(extract-raising-headless-test)
