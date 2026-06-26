;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; CI entry point: run ALL headless integration tests in a FRESH sbcl, exiting
;;; non-zero on any failure.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/run-headless.lisp
;;;
;;; Do NOT --load this in a live session: it resets cgraph state and calls
;;; sb-ext:exit. From a live SLIME session, instead load test/headless-runner.lisp
;;; once and call (cg-from-parse::run-headless-interactive), which restores your
;;; catalog + context and never exits.

(in-package :cg-from-parse)

(load (merge-pathnames "headless-runner.lisp"
                       (or *load-truename* *compile-file-truename*)))

(unless (run-headless-tests) (sb-ext:exit :code 1))
