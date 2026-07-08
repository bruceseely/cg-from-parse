;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live PP-adjunct check: locative and instrumental PPs.
;;; A PP the verb does NOT license as a case ("in the city" / "with the telescope"
;;; -- `see' fills neither slot from a PP here) is NOT dropped: PARSIFAL attaches
;;; it to the CLAUSE as a surface `pp' daughter (this is Marcus's own gram5
;;; PP-UNDER-S rule -- NOT a grammar extension of ours). The extractor walks those
;;; clause pp daughters (clause-adjuncts), maps the preposition to a relation, and
;;; emits it off the predicate:
;;;   "... in the city ."       -> (loc)->[CITY: #]         (locative preposition)
;;;   "... with the telescope ." -> (inst)->[TELESCOPE: #]  (instrument; see's own
;;;                                 canonical graph is (inst)->[OBJECT])
;;; loc is ⊤ -> place and inst is event -> entity; `city' (a place) and `telescope'
;;; (a tool) are in test-types, so this runs strict (:error). man/dog/see/in/with/
;;; telescope are dictionary-driven; `city' gets a small df.
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
        (plain (%pp-adjunct-graph "the man sees the dog .")))
    (let ((pass (and loc inst plain
                     ;; locative PP -> (loc)->[CITY]
                     (search "SEE" loc) (search "(AGNT)→[MAN" loc)
                     (search "(OBJ)→[DOG" loc) (search "(LOC)→[CITY" loc)
                     ;; instrumental PP -> (inst)->[TELESCOPE]
                     (search "(INST)→[TELESCOPE" inst) (search "(OBJ)→[DOG" inst)
                     ;; control: no PP -> no loc/inst arc, still a clean parse
                     (search "SEE" plain)
                     (not (search "LOC" plain)) (not (search "INST" plain)))))
      (when verbose
        (format t "~&locative:   ~a~%instrument: ~a~%without:    ~a~%" loc inst plain))
      (format t "~&extract-pp-adjunct-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
      pass)))

(extract-pp-adjunct-headless-test)
