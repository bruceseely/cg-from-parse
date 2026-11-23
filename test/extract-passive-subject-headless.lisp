;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live PASSIVE SUBJECT check: a passive's surface subject keeps its referent.
;;;
;;;   "the pie was eaten ."      -> (obj)->[PIE: #n]       "The pie was eaten."
;;;   "mitch was seen ."         -> (obj)->[PERSON: Mitch] "Mitch was seen."
;;;   "the pies were eaten ."    -> (obj)->[PIE: {*}]
;;;
;;; A passive's subject is preposed: the case frame holds only its TRACE, in
;;; object position, so the trace is reached before its antecedent ever is.
;;; EMIT-TRACE used to build that antecedent from its bare lemma, dropping the
;;; determiner, number, count and name -- every passive came out indefinite
;;; ("A pie was eaten.", and "the pie was not eaten" as "No pie was eaten."),
;;; and a named subject as a type of its own ([MITCH]). It now emits the
;;; antecedent as the ordinary filler it is.
;;;
;;; Invocation:
;;;   sbcl --noinform --non-interactive \
;;;     --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-passive-subject-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(defun extract-passive-subject-headless-test (&optional (verbose t))
  (let ((results t))
    (dolist (case '(("the pie was eaten ."             "(OBJ)→[PIE:#]"         "The pie was eaten.")
                    ("a pie was eaten ."               "(OBJ)→[PIE]."          "A pie was eaten.")
                    ("the pies were eaten ."           "(OBJ)→[PIE:{*}]"       nil)
                    ("mitch was seen ."                "(OBJ)→[PERSON:MITCH]"  "Mitch was seen.")
                    ("the pie was eaten by the girl ." "(OBJ)→[PIE:#]"         "The pie was eaten by the girl.")
                    ("the pie was not eaten ."         "(OBJ)→[PIE:#]"         "The pie was not eaten.")))
      (destructuring-bind (sentence expected said-expected) case
        (handler-bind ((warning #'muffle-warning))
          (let* ((graph (ignore-errors (parse-and-extract sentence :on-missing :create)))
                 (text  (and graph (without-individual-ids
                                    (remove #\Space (string-upcase (cg-text graph))))))
                 (said  (and graph (ignore-errors (say-graph graph))))
                 (pass  (and text (search expected text)
                             (or (null said-expected) (equal said said-expected)))))
            (when (or verbose (not pass))
              (format t "~&  ~:[FAIL~;pass~]  ~a~%        ~a~%        ~a~%"
                      pass sentence text said))
            (setf results (and pass results))))))
    (format t "~&extract-passive-subject-headless-test: ~:[FAILED <<<~;passed~]~%" results)
    results))

(extract-passive-subject-headless-test t)
