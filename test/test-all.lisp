;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Minimal test driver, mirroring the convention used in :parsifal and
;;; :cgraph: each <name>-test file defines a function NAME returning non-nil
;;; on pass, and test-all iterates the list calling each.

(in-package :cg-from-parse)

(defun test-one (name &optional verbose)
  (let* ((text (format nil "-=- ~a " name))
         (pass (ignore-errors
                (let ((*standard-output* (make-broadcast-stream)))
                  (funcall name)))))
    (when (or verbose (not pass))
      (format t "~&~28a ~:[failed <<<~;passed~]~%" text pass))
    pass))

(defun test-all (&optional verbose)
  (let ((results t)
        (test-names '(extract-test)))
    (dolist (test-name test-names)
      (setf results (and (test-one test-name verbose) results)))
    results))
