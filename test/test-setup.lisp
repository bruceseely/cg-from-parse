;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Shared headless test setup: load cgraph's TEST-TYPES catalog into a fresh
;;; context, non-destructively.
;;;
;;; Tests use test-types on purpose: the user's own ontology (cgraph-types) is
;;; customizable and may not contain the types a test needs. But we must NOT
;;; leave the user's environment changed -- `setup-cgraph :external-types-
;;; directory X` re-symlinks ~/.cgraph/types -> X and never restores it. So
;;; instead of symlinking, we dynamically bind *cgraph-types-directory* to
;;; test-types and let reset-cgraph load straight from there: the catalog loads
;;; into memory and the ~/.cgraph/types symlink is never touched.

(in-package :cg-from-parse)

(defun setup-test-cgraph ()
  "Bring up a cgraph context with the TEST-TYPES catalog, without repointing the
user's ~/.cgraph/types symlink. *package* must be :cg while loading (cgraph's
type loaders use plain READ)."
  (let ((*package* (find-package :conceptual-graphs))
        (cg::*external-types-directory* nil)
        (cg::*cgraph-types-directory*
          (format nil "~atest/test-types/" (asdf:system-source-directory :cgraph))))
    (cg::reset-cgraph)))
