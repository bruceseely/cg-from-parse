;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; Live POSSESSION check: "the girl has a ball ." is [BALL]<-(poss)<-[GIRL],
;;; the same graph the GENITIVE "the girl 's ball" produces, because the two
;;; say the same thing.
;;;
;;; Possession is a RELATION, not an event. Before this, emit-clause treated
;;; `have' like any main verb and went looking for a concept type to serve as
;;; the predicate -- "no concept type for lemma HAVE" -- when there is no
;;; [HAVE] concept to find and never should be.
;;;
;;; A possessor may equally be a NAME ("mitch has a ball ." -> [BALL]<-(poss)<-
;;; [PERSON: Mitch]), a bound gap or a wh-query: what the guard below is really
;;; about is the embedded CLAUSE, not the common noun.
;;;
;;; The guards matter as much as the happy path:
;;;
;;;   "the girl has to go ."       OBLIGATION, not possession. `have' carries
;;;                                inf-obj/to-less-inf-obj features, so its
;;;                                neutral case here is a :clause. Reading that
;;;                                as possession would say the girl possesses a
;;;                                going. It must NOT take the poss path.
;;;   "the girl has scheduled ..." PERFECT AUXILIARY. `has' is the aux and the
;;;                                predicate is the real verb, so possession
;;;                                must not touch it.
;;;
;;; TENSE IS DROPPED on purpose: a `poss' relation carries none, so "had a
;;; ball" and "has a ball" come out alike -- the same limitation the genitive
;;; already has, which keeps the two consistent.
;;;
;;; Invocation:
;;;   sbcl --noinform --non-interactive \
;;;     --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-possession-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun %possession-graph (sentence &optional (on-missing :create))
  "Parse SENTENCE, return its formatted CG upcased with spaces removed, or NIL."
  (when (pa::parse-sentence sentence
                            :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let ((*on-missing-type* on-missing))
      (handler-bind ((warning #'muffle-warning))
        (let ((text (ignore-errors (cg::format-cgraph (ir->cgraph (parse->ir pa::c))))))
          (values (and (stringp text) (remove #\Space (string-upcase text)))
                  text))))))

(defun extract-possession-headless-test (&optional (verbose t))
  (let* ((have     (%possession-graph "the girl has a ball ." :error))
         (past     (%possession-graph "the girl had a ball ." :error))
         ;; a NAMED possessor -- mitch is in the dictionary, PERSON in test-types
         (named    (%possession-graph "mitch has a ball ." :error))
         (genitive (%possession-graph "the boy sees the girl 's ball ." :error))
         ;; obligation: must NOT become possession. Run :create so a missing
         ;; HAVE type cannot mask the check -- we want to see what it emits.
         (oblig    (%possession-graph "the girl has to go ." :create))
         (pass (and have past genitive named
                    ;; the possessed thing is the head, with the owner on a poss
                    (search "[BALL" have)
                    (search "(POSS)←[GIRL" have)
                    ;; and there is no predicate concept: possession is not an event
                    (not (search "[HAVE" have))
                    ;; tense is dropped -- past reads the same as present
                    (string= have past)
                    ;; the genitive is untouched and uses the same relation
                    (search "(OBJ)→[BALL" genitive)
                    (search "(POSS)←[GIRL" genitive)
                    ;; a possessor with a NAME is a possessor. The guard used to
                    ;; demand a common noun on BOTH sides, so every named owner
                    ;; fell through to the event path and died looking for a
                    ;; concept type for HAVE.
                    (search "[BALL" named)
                    (search "(POSS)←[PERSON:MITCH" named)
                    (not (search "[HAVE" named))
                    ;; obligation is NOT possession: `go' survives as a predicate
                    oblig
                    (search "GO" oblig)
                    (not (search "(POSS)" oblig)))))
    (when verbose
      (format t "~&have:      ~a~%past:      ~a~%named:     ~a~%genitive:  ~a~%oblig:     ~a~%"
              have past named genitive oblig))
    (format t "~&extract-possession-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
    pass))

(extract-possession-headless-test t)
