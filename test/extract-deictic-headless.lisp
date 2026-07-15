;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live DEICTIC-adverb check: here / there (place) and today / now (time).
;;; Deictic adverbs are lexicalized in Marcus's dictionary as pseudopropnoun
;;; place/time NOUNS (defs-dictionary.dict), so PARSIFAL does not drop them:
;;;   - PLACE deictics (here/there) land as a stray `np' daughter of the VP --
;;;     NOT a case (no verb slot licenses them) and NOT a PP. Nothing walked
;;;     those until clause-deictic-adjuncts: it takes each non-case VP `np' whose
;;;     head is a place/time pseudopropnoun and emits it off the predicate like a
;;;     PP adjunct.  "... here ." -> (loc)->[HERE];  "... there ." -> (loc)->[THERE].
;;;   - TIME deictics (today/now) instead arrive wrapped by PARSIFAL in a synthetic
;;;     `during' PP, so the ordinary PP-adjunct path (clause-adjuncts) already
;;;     handles them:  "... today ." -> (time)->[TODAY];  "... now ." -> (time)->[NOW].
;;; loc is ⊤->place (see ⊑ act ⊑ event, and place fits loc's dest); time is
;;; situation->time-period. `here'/`there' are added to cgraph test-types (⊑ place),
;;; so the place cases run strict (:error). TODAY/NOW are not test-types (they are
;;; deictic, created on the fly under time-period), so those two run under :create
;;; -- exactly as the manner-adverb test does for `quickly'. man/dog/see/here/there/
;;; today/now are all dictionary-driven; no df is needed.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-deictic-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun %deictic-graph (sentence &optional (on-missing :error))
  "Parse SENTENCE, return its formatted CG upcased with spaces removed, or NIL."
  (when (pa::parse-sentence sentence
                            :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let ((*on-missing-type* on-missing))
      (handler-bind ((warning #'muffle-warning))
        (let ((text (ignore-errors (cg::format-cgraph (ir->cgraph (parse->ir pa::c))))))
          (values (and (stringp text) (remove #\Space (string-upcase text)))
                  text))))))

(defun extract-deictic-headless-test (&optional (verbose t))
  (let ((here  (%deictic-graph "the man sees the dog here ."))          ; strict
        (there (%deictic-graph "the man sees the dog there ."))         ; strict
        (today (%deictic-graph "the man sees the dog today ." :create)) ; PP path
        (now   (%deictic-graph "the man sees the dog now ."   :create)) ; PP path
        (plain (%deictic-graph "the man sees the dog .")))
    (let ((pass (and here there today now plain
                     ;; place deictic `here' -> (loc)->[HERE], object intact
                     (search "SEE" here) (search "(AGNT)→[MAN" here)
                     (search "(OBJ)→[DOG" here) (search "(LOC)→[HERE" here)
                     (not (search "TIME" here))
                     ;; place deictic `there' -> (loc)->[THERE]
                     (search "(LOC)→[THERE" there) (search "(OBJ)→[DOG" there)
                     ;; time deictic `today' -> (time)->[TODAY] (via `during' PP)
                     (search "(TIME)→[TODAY" today) (not (search "LOC" today))
                     ;; time deictic `now' -> (time)->[NOW]
                     (search "(TIME)→[NOW" now) (not (search "LOC" now))
                     ;; control: no deictic -> no loc/time arc, still a clean parse
                     (search "SEE" plain)
                     (not (search "LOC" plain)) (not (search "TIME" plain)))))
      (when verbose
        (format t "~&here:  ~a~%there: ~a~%today: ~a~%now:   ~a~%plain: ~a~%"
                here there today now plain))
      (format t "~&extract-deictic-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
      pass)))

(extract-deictic-headless-test)
