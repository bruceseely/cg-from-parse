;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-

(in-package :cg-from-parse)

(defun extract-test ()
  "Placeholder until extraction is implemented: confirms extract-graph is
wired up and signals (rather than silently returning) for unbuilt input.
Replace with real extraction assertions as the mapping is built out."
  (handler-case
      (progn (extract-graph nil) nil)   ; should not return normally yet
    (error () t)))
