;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Shared runner for the headless integration tests. Loading THIS file only
;;; defines functions -- it runs nothing -- so it is safe to load into a live
;;; SLIME session.
;;;
;;;   run-headless-tests (&key restore)
;;;     Load each extract-*-headless.lisp in turn (each self-sets-up its
;;;     test-types catalog + PARSIFAL grammar and runs itself, printing a line),
;;;     capture pass/fail, print a rollup, and return T iff all passed.
;;;     With :restore t, reload your own type catalog + a fresh context on exit
;;;     so the session isn't left sitting on test-types.
;;;
;;;   run-headless-interactive
;;;     run-headless-tests :restore t -- the safe entry point for a live session.
;;;
;;; The CI entry point is test/run-headless.lisp, which loads this and calls
;;; run-headless-tests, exiting non-zero on failure.

(in-package :cg-from-parse)

(defparameter *headless-tests*
  '(("emit"         . extract-emit-headless-test)
    ("live"         . extract-live-headless-test)
    ("coref"        . extract-coref-headless-test)
    ("ditransitive" . extract-ditransitive-headless-test)
    ("relative"     . extract-relative-headless-test)
    ("modifier"     . extract-modifier-headless-test)
    ("genitive"     . extract-genitive-headless-test)
    ("apposition"   . extract-apposition-headless-test)
    ("pp-adjunct"   . extract-pp-adjunct-headless-test)
    ("adverb"       . extract-adverb-headless-test)
    ("passive"      . extract-passive-headless-test)
    ("determiner"   . extract-determiner-headless-test)
    ("quantifier"   . extract-quantifier-headless-test)
    ("named"        . extract-named-headless-test)
    ("number"       . extract-number-headless-test)
    ("question"     . extract-question-headless-test)
    ("yesno"        . extract-yesno-headless-test)
    ("imperative"   . extract-imperative-headless-test)
    ("raising"      . extract-raising-headless-test)
    ("stative"      . extract-stative-headless-test)
    ("complement"   . extract-complement-headless-test)
    ("driver"       . extract-driver-headless-test))
  "(label . test-function) for each extract-<label>-headless.lisp script.")

(defun run-headless-tests (&key restore)
  "Run all headless integration tests; print a rollup; return T iff all passed.
See file header. RESTORE reloads your catalog + a fresh context afterward."
  (let ((test-dir        (asdf:system-relative-pathname :cg-from-parse "test/"))
        (saved-types-dir cg::*cgraph-types-directory*)   ; your catalog dir
        (results '()))
    (unwind-protect
         (dolist (spec *headless-tests*)
           (let ((file (merge-pathnames (format nil "extract-~a-headless.lisp" (car spec))
                                        test-dir)))
             ;; The load runs the test once (printing its line) and leaves its
             ;; grammar current; re-run quietly to capture pass/fail. ignore-errors
             ;; so one broken test can't abort the rest of the run.
             (push (cons (car spec)
                         (ignore-errors
                          (load file)
                          (let ((*standard-output* (make-broadcast-stream)))
                            (funcall (cdr spec)))))
                   results)))
      (when restore
        ;; Reload the user's catalog into memory with a fresh context, so a live
        ;; session isn't left on test-types. (*package* must be :cg while loading
        ;; -- cgraph's type loaders use plain READ.) NB: this resets *context*,
        ;; clearing any in-memory graphs; it restores your TYPE catalog.
        (let ((*package*                  (find-package :conceptual-graphs))
              (cg::*cgraph-types-directory* saved-types-dir))
          (ignore-errors (cg::reset-cgraph)))))
    (setf results (nreverse results))
    (format t "~2&==== headless summary ====~%")
    (dolist (r results)
      (format t "  ~:[FAIL <<<~;pass~]  ~a~%" (cdr r) (car r)))
    (let ((passed (count-if #'cdr results)) (total (length results)))
      (format t "  ~d/~d passed~%" passed total)
      (= passed total))))

(defun run-headless-interactive ()
  "Run all headless tests from a live session, restoring your catalog + context
afterward. Prints a rollup; returns T iff all passed."
  (run-headless-tests :restore t))
