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
           ;; Final punctuation: supplied when missing, and `!' ends a sentence.
           ;; None of it changes the graph.
           (t-bare  (ignore-errors (string-upcase (cg::format-cgraph
                                                   (parse-and-extract "the man sees the dog")))))
           (t-space (ignore-errors (string-upcase (cg::format-cgraph
                                                   (parse-and-extract "the man sees the dog   ")))))
           (t-bang  (ignore-errors (string-upcase (cg::format-cgraph
                                                   (parse-and-extract "the man sees the dog !")))))
           (t-q     (ignore-errors (string-upcase (cg::format-cgraph
                                                   (parse-and-extract "does the man see the dog")))))
           ;; Each parse mints a new event id (#5, #12 ...), and the formatter
           ;; indents the arcs by the head's width; compare without either.
           (punct-pass (and (flet ((same (a)
                                     (flet ((norm (x) (remove-if (lambda (c) (member c '(#\Space #\Newline)))
                                                                 (cl-ppcre:regex-replace-all "#\\d+" x "#"))))
                                       (and a t1 (equal (norm a) (norm t1))))))
                              (and (same t-bare) (same t-space) (same t-bang) (same t-q)))
                            (equal (ensure-final-punctuation "a b ?") "a b ?")
                            (equal (ensure-final-punctuation "a b.") "a b.")
                            (equal (ensure-final-punctuation "a b ") "a b .")))
           (pass (and t1 (search "SEE" t1) (search "MAN" t1) (search "DOG" t1)
                      (search "AGNT" t1) (search "OBJ" t1)
                      ;; "to go" is an infinitival -> SITUATION wrapper (#7)
                      t2 (search "PERSUADE" t2) (search "SITUATION" t2)
                      (search "GIRL" t2)
                      punct-pass)))
      (when verbose
        (format t "~&(parse-and-extract \"the man sees the dog .\"):~%~a~%"
                (and g1 (cg::format-cgraph g1)))
        (format t "~&(parse-and-extract \"the boy persuaded the girl to go .\"):~%~a~%"
                (and g2 (cg::format-cgraph g2)))
        (format t "~&final punctuation supplied / `!' / unpunctuated question: ~:[FAIL~;pass~]~%  ~s~%  ~s~%  ~s~%"
                punct-pass t-bare t-bang t-q))
      (format t "~&extract-driver-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
      pass)))

(extract-driver-headless-test)
