;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-

(in-package :cg-from-parse)

(defun extract-test ()
  "Unit-test the runtime-free pieces of the extractor (the case-role -> relation
mapping). The full IR->cgraph emission and the live parse->IR reader are
exercised by the headless integration script test/extract-emit-headless.lisp,
which needs a live cgraph (and, for the reader, a live parser) image."
  (and (eq (case-role->relation 'pa::agt)  'cg::agnt)
       (eq (case-role->relation 'pa::neut) 'cg::obj)
       (eq (case-role->relation 'pa::dat)  'cg::rcpt)
       (null (case-role->relation 'pa::nonesuch))))
