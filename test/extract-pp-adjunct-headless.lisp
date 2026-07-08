;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live PP-adjunct check: locative, instrumental, and temporal PPs.
;;; A PP the verb does NOT license as a case ("in the city" / "with the telescope"
;;; / "on monday" -- `see' fills no slot from these) is NOT dropped: PARSIFAL
;;; attaches it to the CLAUSE as a surface `pp' daughter (this is Marcus's own
;;; gram5 PP-UNDER-S rule -- NOT a grammar extension of ours). The extractor walks
;;; those clause pp daughters (clause-adjuncts), resolves each preposition to a
;;; relation, and emits it off the predicate:
;;;   "... in the city ."        -> (loc)->[CITY: #]        (locative preposition)
;;;   "... with the telescope ." -> (inst)->[TELESCOPE: #]  (instrument; see's own
;;;                                 canonical graph is (inst)->[OBJECT])
;;;   "... on monday ."          -> (time)->[MONDAY: #]     (AMBIGUOUS prep `on' --
;;;                                 locative on the mat, temporal on monday --
;;;                                 resolved to `time' by the time-NP object)
;;;   "... before monday ."      -> (time)->[MONDAY: #]     (dedicated temporal prep)
;;; loc is ⊤->place, inst is event->entity, time is situation->time-period (and
;;; see ⊑ act ⊑ event ⊑ situation). `city' (place), `telescope' (tool), `monday'
;;; (time-period) are in test-types, so this runs strict (:error). man/dog/see/in/
;;; with/on/before/telescope/monday are dictionary-driven; `city' gets a small df.
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-pp-adjunct-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)
;; `city' (a place) is not in PARSIFAL's dictionary; supply a small df.
(pa::df pa::city pa::feats (pa::noun pa::ns pa::n3p) pa::markers (pa::physob))
(pa::expandsim 'pa::city)

(defun %pp-adjunct-graph (sentence &optional (on-missing :error))
  "Parse SENTENCE, return its formatted CG upcased with spaces removed, or NIL."
  (when (pa::parse-sentence sentence
                            :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let ((*on-missing-type* on-missing))
      (handler-bind ((warning #'muffle-warning))
        (let ((text (ignore-errors (cg::format-cgraph (ir->cgraph (parse->ir pa::c))))))
          (values (and (stringp text) (remove #\Space (string-upcase text)))
                  text))))))

(defun extract-pp-adjunct-headless-test (&optional (verbose t))
  (let ((loc   (%pp-adjunct-graph "the man sees the dog in the city ."))
        (inst  (%pp-adjunct-graph "the man sees the dog with the telescope ."))
        (tobj  (%pp-adjunct-graph "the man sees the dog on monday ."))
        (tprep (%pp-adjunct-graph "the man sees the dog before monday ."))
        (plain (%pp-adjunct-graph "the man sees the dog .")))
    (let ((pass (and loc inst tobj tprep plain
                     ;; locative PP -> (loc)->[CITY]
                     (search "SEE" loc) (search "(AGNT)→[MAN" loc)
                     (search "(OBJ)→[DOG" loc) (search "(LOC)→[CITY" loc)
                     ;; instrumental PP -> (inst)->[TELESCOPE]
                     (search "(INST)→[TELESCOPE" inst) (search "(OBJ)→[DOG" inst)
                     ;; temporal, ambiguous prep `on' + time object -> (time)->[MONDAY]
                     (search "(TIME)→[MONDAY" tobj) (not (search "LOC" tobj))
                     ;; temporal, dedicated prep `before' -> (time)->[MONDAY]
                     (search "(TIME)→[MONDAY" tprep)
                     ;; control: no PP -> no adjunct arc, still a clean parse
                     (search "SEE" plain)
                     (not (search "LOC" plain)) (not (search "INST" plain))
                     (not (search "TIME" plain)))))
      (when verbose
        (format t "~&locative:   ~a~%instrument: ~a~%temporal(obj):  ~a~%temporal(prep): ~a~%without: ~a~%"
                loc inst tobj tprep plain))
      (format t "~&extract-pp-adjunct-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
      pass)))

(extract-pp-adjunct-headless-test)
