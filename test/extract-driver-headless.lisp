;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live check of the ergonomic driver: parse-and-extract does the whole
;;; string -> conceptual-graph trip (load + register the full grammar, parse,
;;; extract) -- NO per-construction grammar registration by the caller. One
;;; loaded grammar handles different constructions.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-driver-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)
;; Note: no clause-grammar load / register-grammar here -- the driver does it.

(defun extract-driver-headless-test (&optional (verbose t))
  (handler-bind ((warning #'muffle-warning))
    (let* ((g1 (ignore-errors (parse-and-extract "the man sees the dog .")))
           (t1 (and g1 (ignore-errors (string-upcase (cg::format-cgraph g1)))))
           ;; a different construction through the SAME loaded grammar
           (g2 (ignore-errors (parse-and-extract "the boy persuaded the girl to go ."
                                                 :on-missing :create)))
           (t2 (and g2 (ignore-errors (string-upcase (cg::format-cgraph g2)))))
           (pass (and t1 (search "SEE" t1) (search "MAN" t1) (search "DOG" t1)
                      (search "AGNT" t1) (search "OBJ" t1)
                      t2 (search "PERSUADE" t2) (search "PROPOSITION" t2)
                      (search "GIRL" t2))))
      (when verbose
        (format t "~&(parse-and-extract \"the man sees the dog .\"):~%~a~%"
                (and g1 (cg::format-cgraph g1)))
        (format t "~&(parse-and-extract \"the boy persuaded the girl to go .\"):~%~a~%"
                (and g2 (cg::format-cgraph g2))))
      (format t "~&extract-driver-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
      pass)))

(extract-driver-headless-test)
