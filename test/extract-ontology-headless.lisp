;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; ONTOLOGY-CONTRACT check: validate-ontology + the *ontology-requirements*
;;; manifest. The extractor writes graphs over a fixed set of framework relations
;;; and abstract concept types (agnt/obj/loc..., person/proposition/...) it names
;;; structurally. `validate-ontology' checks the LOADED ontology provides them, so
;;; a mismatched ontology is a loud up-front diagnostic rather than a mid-sentence
;;; failure. This test pins the mechanism:
;;;   1. The reference test-types satisfy the :full contract (nothing missing) --
;;;      this also proves the manifest lists only REAL framework vocabulary (every
;;;      declared label resolves), i.e. the manifest hasn't drifted to name a type
;;;      or relation that no longer exists.
;;;   2. The presence detector really discriminates: a known type/relation resolves,
;;;      a bogus one does not (so an all-green report is not a rubber stamp).
;;;   3. Profiles: :full is known; an unknown profile errors (naming the known ones).
;;;   4. Every manifest entry is well-formed (has a :desc and requires something).
;;; It does NOT (yet) catch UNDER-declaration -- a framework label the extractor
;;; emits but the manifest forgot; that needs runtime capture and is future work.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-ontology-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(defun extract-ontology-headless-test (&optional (verbose t))
  (let* ((quiet (make-broadcast-stream))                 ; discard the report unless verbose
         (stream (if verbose *standard-output* quiet)))
    (multiple-value-bind (ok missing) (validate-ontology :profile :full :stream stream)
      (let ((pass
              (and
               ;; 1. reference ontology satisfies the full contract
               ok (null missing)
               ;; 2. the detector discriminates (not an always-true rubber stamp)
               (ontology-has-type-p 'person) (ontology-has-relation-p 'agnt)
               (not (ontology-has-type-p 'definitely-not-a-real-type))
               (not (ontology-has-relation-p 'definitely-not-a-real-relation))
               ;; 3. profiles: :full known, unknown errors
               (eq (construction-tags :full) :all)
               (nth-value 1 (ignore-errors (construction-tags :no-such-profile)))
               ;; 4. every manifest entry is well-formed
               (every (lambda (entry)
                        (destructuring-bind (tag &key relations concept-types
                                                 conventions desc) entry
                          (and (keywordp tag) (stringp desc)
                               (or relations concept-types conventions))))
                      *ontology-requirements*))))
        (when verbose
          (format t "~&validate-ontology :full -> ok=~a missing=~a~%" ok missing))
        (format t "~&extract-ontology-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
        pass))))

(extract-ontology-headless-test)
