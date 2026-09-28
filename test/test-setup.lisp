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

;;; --- comparing graphs across extractions -----------------------------------
;;;
;;; Event individuation (system/identity.lisp) gives every extracted event its
;;; own individual marker, so [EAT: #2] and [EAT: #4] are two eatings. That is
;;; the point of it -- and it means TWO EXTRACTIONS OF THE SAME SENTENCE no
;;; longer produce the same string, because the markers come off a global
;;; counter. A test that compares two extractions for identical text is asking
;;; whether they have the same STRUCTURE, never whether they drew the same
;;; marker, so it compares them through here.
;;;
;;; Only "#<digits>" collapses to "#". The bare "#" of a definite entity
;;; ([MAN: #], build-referent's `:id t') is already stable and is left alone.

(defun without-individual-ids (string)
  "STRING with every numbered individual marker (#12) reduced to a bare #, so
two extractions of the same content compare EQUAL. NIL passes through."
  (when (stringp string)
    (with-output-to-string (out)
      (let ((i 0) (n (length string)))
        (loop while (< i n) do
          (let ((ch (char string i)))
            (write-char ch out)
            (incf i)
            (when (char= ch #\#)
              ;; swallow the digits that follow the marker
              (loop while (and (< i n) (digit-char-p (char string i)))
                    do (incf i)))))))))
