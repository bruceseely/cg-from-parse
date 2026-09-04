;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live PROGRESSIVE aspect check -- the last of roadmap §1's open aspects:
;;;   "the girl is eating pie ."   -> [EAT: @present-progressive]
;;;   "the girl was eating pie ."  -> [EAT: @past-progressive]
;;;
;;; This needed BOTH layers. The parser could not read a progressive at all
;;; until 2026-09-04: parsifal's port had never registered Marcus's PROGRESSIVE
;;; rule ([=*be][=ing] IN BUILD-AUX, gram1:115), so `is' was taken as the main
;;; verb and `eating' stranded (see parsifal gram1-progressive-test, and
;;; cg-from-parse's own diagnose-parse, which is how the gap was found). With
;;; the rule in place the aux node is labelled `prog', and this side maps that
;;; to cgraph's :progressive aspect -- both features live on the SAME aux node,
;;; so perf+prog is :perfect-progressive (spec-aspect).
;;;
;;; Aspect is a concept SLOT, and since cgraph 74d0411 the formatter also emits
;;; it as an @-word compounded with the tense, so both are checked here. The
;;; round trip is checked too: cgraph's realizer builds the periphrasis back
;;; ("is eating"), so the progressive survives English -> graph -> English.
;;;
;;; girl/eat/pie are all test-types, so the two progressive cases run STRICT
;;; (:error). The perfect control uses :create -- schedule/meeting are not in
;;; the catalog -- and is here to guard the aspect mapping's other branch.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-progressive-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(defun %aspect-info (sentence &optional (on-missing :error))
  "Return (values aspect tense text) for SENTENCE's predicate concept."
  (let* ((graph (ignore-errors (parse-and-extract sentence :on-missing on-missing)))
         (pred  (and graph (cg::head graph))))
    (values (and pred (ignore-errors (cg::concept-aspect pred)))
            (and pred (ignore-errors (cg::concept-tense pred)))
            (and graph (ignore-errors (string-upcase (cg-text graph)))))))

(defun extract-progressive-headless-test (&optional (verbose t))
  (handler-bind ((warning #'muffle-warning))
    (multiple-value-bind (pres-a pres-t pres-x) (%aspect-info "the girl is eating pie .")
      (multiple-value-bind (past-a past-t past-x) (%aspect-info "the girl was eating pie .")
        (multiple-value-bind (simp-a simp-t simp-x) (%aspect-info "the girl eats pie .")
          (multiple-value-bind (perf-a perf-t)
              (%aspect-info "the boy should have scheduled the meeting ." :create)
            (let* ((said (ignore-errors (sentence->say "the girl is eating pie .")))
                   (pass (and
                          ;; present progressive: slot + @-word, tense unaffected
                          (eq pres-a :progressive) (eq pres-t :present)
                          pres-x (search "@PRESENT-PROGRESSIVE" pres-x)
                          (search "[EAT" pres-x) (search "(AGNT)→[GIRL" pres-x)
                          (search "(OBJ)→[PIE" pres-x)
                          ;; past progressive: the tense comes off `was'
                          (eq past-a :progressive) (eq past-t :past)
                          past-x (search "@PAST-PROGRESSIVE" past-x)
                          ;; the simple present is still simple (no aspect at all)
                          (null simp-a) (eq simp-t :present)
                          simp-x (search "@PRESENT" simp-x)
                          (not (search "PROGRESSIVE" simp-x))
                          ;; the other branch of the mapping still reads perfect
                          (eq perf-a :perfect) (eq perf-t :past)
                          ;; round trip: the realizer rebuilds the periphrasis
                          (stringp said) (search "is eating" said))))
              (when verbose
                (format t "~&is eating:  ~s/~s  ~a" pres-t pres-a pres-x)
                (format t "~&was eating: ~s/~s  ~a" past-t past-a past-x)
                (format t "~&eats:       ~s/~s  ~a" simp-t simp-a simp-x)
                (format t "~&perfect control: ~s/~s~%" perf-t perf-a)
                (format t "~&say: ~a~%" said))
              (format t "~&extract-progressive-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
              pass)))))))

(extract-progressive-headless-test)
