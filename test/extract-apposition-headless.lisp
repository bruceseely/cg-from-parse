;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live apposition check: "the dog , spot sees the woman ."
;;; PARSIFAL now parses apposition (parsifal *apposition-rules* -- OUR extension,
;;; the first non-Marcus grammar rule: APPOSITIVE attaches a `, NAME' to a
;;; just-completed common-noun NP as its `appos' daughter, keeping the head noun's
;;; own type). The extractor reads the appositive name off the head NP
;;; (np-appos-name) and makes the entity a NAMED individual of its OWN type:
;;;   [SEE]-(agnt)->[DOG: Spot] (obj)->[WOMAN: #].
;;; The point of apposition: a bare name only gets the name marker's BROAD type
;;; (hanim/anim -> [ANIMAL: Spot]); apposition supplies the SPECIFIC type [DOG:
;;; Spot] from the head noun. dog/woman/see are all in test-types, so this runs
;;; strict (:error); `spot' (a proper name) is supplied with a small df, as
;;; PARSIFAL's own gram1-proper-noun-test supplies `John'.
;;;
;;; Also checks apposition in OBJECT position ("... sees the dog , spot .").
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-apposition-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)
;; `spot' is not in PARSIFAL's dictionary; supply it as a proper name (hanim).
(pa::df pa::spot pa::feats (pa::name pa::ns pa::n3p) pa::markers (pa::hanim))
(pa::expandsim 'pa::spot)

(defun %apposition-graph (sentence &optional (on-missing :error))
  "Parse SENTENCE, return its formatted CG upcased with spaces removed, or NIL."
  (when (pa::parse-sentence sentence
                            :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let ((*on-missing-type* on-missing))
      (handler-bind ((warning #'muffle-warning))
        (let ((text (ignore-errors (cg::format-cgraph (ir->cgraph (parse->ir pa::c))))))
          (values (and (stringp text) (remove #\Space (string-upcase text)))
                  text))))))

(defun extract-apposition-headless-test (&optional (verbose t))
  (multiple-value-bind (subj text1) (%apposition-graph "the dog , spot sees the woman .")
    (multiple-value-bind (obj text2) (%apposition-graph "the woman sees the dog , spot .")
      (let ((pass (and subj obj
                       ;; subject apposition: agent is [DOG: Spot], not [DOG: #]
                       (search "SEE" subj) (search "WOMAN" subj)
                       (search "(AGNT)→[DOG:SPOT" subj)
                       ;; object apposition: object is [DOG: Spot]
                       (search "(OBJ)→[DOG:SPOT" obj))))
        (when verbose
          (format t "~&subject apposition:~%~a~%object apposition:~%~a~%"
                  text1 text2))
        (format t "~&extract-apposition-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
        pass))))

(extract-apposition-headless-test)
