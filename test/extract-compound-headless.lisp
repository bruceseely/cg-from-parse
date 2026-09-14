;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live NOUN-NOUN COMPOUND check: "a cherry pie" is a PIE with a (kind)
;;; modifier, not a bare [CHERRY].
;;;
;;; Before parsifal's NOUN-COMPOUND rule (*noun-compound-rules*), "a cherry
;;; pie" parsed as TWO NPs -- `a cherry' plus a determiner-less `pie' that
;;; NP-DONE labels `bad' -- and this extractor took the first as the object,
;;; emitting [CHERRY] and dropping the head noun. That is the regression this
;;; guards.
;;;
;;; The relation is `kind', NOT `attr'. ATTR's dest-type is ATTRIBUTE and
;;; CHERRY lives under FOOD, so [PIE]->(attr)->[CHERRY] is type-invalid and
;;; would be dropped in silence -- which is precisely the bug that made the
;;; head noun disappear in the first place. Adjective modifiers still emit
;;; ATTR; the extractor chooses by what the parser saw, an `nmod' daughter
;;; rather than an `adj' one.
;;;
;;; Runs strict (:error) -- cherry, pie and `kind' are all in test-types, so a
;;; missing-type fallback here would mean the catalog drifted, and should fail.
;;;
;;; Invocation:
;;;   sbcl --noinform --non-interactive \
;;;     --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-compound-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun %compound-graph (sentence &optional (on-missing :error))
  "Parse SENTENCE, return its formatted CG upcased with spaces removed, or NIL."
  (when (pa::parse-sentence sentence
                            :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let ((*on-missing-type* on-missing))
      (handler-bind ((warning #'muffle-warning))
        (let ((text (ignore-errors (cg::format-cgraph (ir->cgraph (parse->ir pa::c))))))
          (values (and (stringp text) (remove #\Space (string-upcase text)))
                  text))))))

(defun extract-compound-headless-test (&optional (verbose t))
  (multiple-value-bind (cmpd text1) (%compound-graph "the girl eats a cherry pie .")
    (multiple-value-bind (plain text2) (%compound-graph "the girl eats a pie .")
      (let ((pass (and cmpd plain
                       ;; the HEAD survives and is the object
                       (search "(OBJ)→[PIE" cmpd)
                       ;; the modifier hangs off it as (kind)
                       (search "(KIND)→[CHERRY" cmpd)
                       ;; and NOT as attr -- attr would be type-invalid here
                       (not (search "(ATTR)→[CHERRY" cmpd))
                       ;; the regression: the object is not a bare [CHERRY]
                       (not (search "(OBJ)→[CHERRY" cmpd))
                       ;; a single noun is untouched: no kind relation at all
                       (search "(OBJ)→[PIE" plain)
                       (not (search "KIND" plain)))))
        (when verbose
          (format t "~&compound: ~a~%plain:    ~a~%" text1 text2))
        (format t "~&extract-compound-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
        pass))))

(extract-compound-headless-test t)
