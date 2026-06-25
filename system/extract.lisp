;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; extract.lisp — turn PARSIFAL parse products into conceptual graphs.
;;;
;;; Boundary conventions for this bridge layer:
;;;   * reference parser symbols as  pa:…  (package :parsifal / :pa)
;;;   * reference CG symbols as      cg:…  (package :conceptual-graphs / :cg)
;;;   * do NOT (:use …) those packages — keep every crossing explicit.

(in-package :cg-from-parse)

(defun extract-graph (parse)
  "Build a conceptual graph (a :cgraph object) from a PARSIFAL parse product
PARSE (e.g. a completed parse node / case-frame structure).

Not yet implemented — this is the scaffold's entry point. The real mapping
from parse-node case frames to concepts/relations lands here."
  (declare (ignore parse))
  (error "cg-from-parse:extract-graph is not yet implemented."))
