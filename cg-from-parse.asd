;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-

;;; cg-from-parse — the bridge layer between PARSIFAL and cgraph.
;;;
;;; It depends on both :parsifal (the parser) and :cgraph (conceptual
;;; graphs); neither of those depends on it. This keeps the parser and the
;;; CG system independently loadable/testable, with all the glue that turns
;;; parse products into conceptual graphs isolated here.
;;;
;;; ASDF resolves :parsifal and :cgraph through the existing source-registry
;;; directive (:tree "~/repo/"), which scans every .asd under ~/repo/. As a
;;; sibling repo there, this system becomes quickloadable automatically:
;;;   (ql:quickload :cg-from-parse)
;;; If ASDF doesn't see it yet, (asdf:clear-source-registry).

(defpackage :cg-from-parse
  (:use #:cl)
  (:nicknames :cfp)
  (:documentation
   "Extract conceptual graphs (:cgraph) from PARSIFAL (:parsifal) parse
    products. Foreign symbols are referenced qualified (cg:… / pa:…) rather
    than via :use, to keep the package boundary explicit and avoid the
    symbol conflicts that :use-ing two large export sets would create.")
  (:export #:extract-graph))

(in-package :asdf-user)

(defsystem "cg-from-parse"
  :description "Extract conceptual graphs from PARSIFAL parse products"
  :version "0.0.1"
  :author "Bruce Seely <bruce@bseely.com>"
  :depends-on (:parsifal :cgraph)
  :perform (test-op (o c) (uiop:symbol-call :cg-from-parse '#:test-all t))
  :components ((:module "system"
                :serial t
                :components ((:file "extract")))
               (:module "test"
                :serial t
                :depends-on ("system")
                :components ((:file "test-all")
                             (:file "extract-test")))))
