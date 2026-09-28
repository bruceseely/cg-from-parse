;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; IDENTITY ACROSS SENTENCES -- event referents + the name registry.
;;;
;;; The failure this covers (notes/kb-experiment-findings.md,
;;; notes/intake-survey-findings.md): extraction used to produce graphs that
;;; could not be accumulated. Put two dozen in one context and include-cgraph
;;; collapsed them into ONE graph with a single [EAT] carrying eight agents,
;;; while "Sue" came out a different person in every sentence -- 28 distinct
;;; individual ids across 29 mentions. Two ends of one failure: nothing in an
;;; extracted graph said WHICH thing it was about.
;;;
;;; Both halves are asserted here, plus the two things that are easy to get
;;; wrong:
;;;
;;;   1. events are individuated, and two eatings are DIFFERENT
;;;   2. a named individual is the SAME object across sentences
;;;   3. within one sentence, coreference still shares ONE concept (the event
;;;      is individuated once, not once per mention)
;;;   4. a definite entity keeps its bare `#' marker -- individuation is about
;;;      EVENTS; `build-referent' is untouched
;;;   5. *individuate-events* NIL restores generic events, which is how you
;;;      extract a QUERY PATTERN (a pattern carrying [EAT: #3] matches only
;;;      that event)
;;;   6. with-fresh-identity isolates a registry; reset-name-registry clears it
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-identity-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(load (merge-pathnames "system/grammar/clause-grammar.lisp"
                       (asdf:system-source-directory :parsifal)))
(pa::load-full-grammar)

(defun %identity-graph (sentence)
  "Parse and extract SENTENCE strictly, or NIL."
  (when (pa::parse-sentence sentence
                            :initial-rule (intern "INITIAL-RULE" :parsifal))
    (let ((*on-missing-type* :error))
      (handler-bind ((warning #'muffle-warning))
        (ignore-errors (ir->cgraph (parse->ir pa::c)))))))

(defun %concepts (graph)
  (remove-if-not (lambda (n) (typep n 'cg::concept)) (cg::nodes graph)))

(defun %named-individual (graph name)
  "The individual behind the concept in GRAPH whose referent names NAME."
  (dolist (c (%concepts graph))
    (when (equal (ignore-errors (cg::referent-name c)) name)
      (return (ignore-errors (cg::content (cg::referent c)))))))

(defun %typed-concept (graph label)
  "The first concept in GRAPH whose type is named LABEL."
  (find label (%concepts graph)
        :test #'string-equal
        :key (lambda (c) (string (cg::label (cg::concept-type c))))))

(defun extract-identity-headless-test (&optional (verbose t))
  (with-fresh-identity
    (let* (;; --- 1 & 2: two sentences, one Sue, two eatings ---------------
           (g1 (%identity-graph "sue eats a pie ."))
           (g2 (%identity-graph "sue sees the dog ."))
           (sue1 (and g1 (%named-individual g1 "Sue")))
           (sue2 (and g2 (%named-individual g2 "Sue")))
           (eat1 (and g1 (%typed-concept g1 "EAT")))
           ;; a SECOND eating, which must not be the first one
           (g3   (%identity-graph "sue eats a pie ."))
           (eat3 (and g3 (%typed-concept g3 "EAT")))
           (eat1-ind (and eat1 (ignore-errors (cg::content (cg::referent eat1)))))
           (eat3-ind (and eat3 (ignore-errors (cg::content (cg::referent eat3)))))

           ;; --- 3: intra-sentence coreference still shares one concept ----
           ;; "the man who sees the dog sees the woman": ONE [MAN], and the two
           ;; SEE events are distinct individuals.
           (gc   (%identity-graph "the man who sees the dog sees the woman ."))
           (men  (and gc (remove-if-not
                          (lambda (c) (string-equal
                                       "MAN" (string (cg::label (cg::concept-type c)))))
                          (%concepts gc))))
           (sees (and gc (remove-if-not
                          (lambda (c) (string-equal
                                       "SEE" (string (cg::label (cg::concept-type c)))))
                          (%concepts gc))))
           (see-ids (and sees (remove nil
                                      (mapcar (lambda (c)
                                                (ignore-errors
                                                 (cg::id (cg::content (cg::referent c)))))
                                              sees))))

           ;; --- 4: a definite entity keeps its bare # -------------------
           (dog (and g2 (%typed-concept g2 "DOG")))
           (dog-id (and dog (ignore-errors (cg::id (cg::content (cg::referent dog))))))

           ;; --- 5: the switch gives generic events back ------------------
           (gen (let ((*individuate-events* nil))
                  (%identity-graph "sue eats a pie .")))
           (gen-eat (and gen (%typed-concept gen "EAT")))

           (pass
            (and
             ;; 1. events individuated, and the two eatings are different
             g1 g3 eat1-ind eat3-ind
             (numberp (cg::id eat1-ind))          ; a NUMBER, not the bare T --
             (numberp (cg::id eat3-ind))          ; [EAT: #] would not individuate
             (not (cg::same-individual-p eat1-ind eat3-ind))
             ;; 2. one Sue, the very same object
             sue1 sue2 (eq sue1 sue2)
             (cg::same-individual-p sue1 sue2)
             ;; 3. coreference intact: one MAN, two distinct SEE events
             gc (eql 1 (length men))
             (eql 2 (length sees))
             (eql 2 (length (remove-duplicates see-ids)))
             ;; 4. definite entity untouched -- bare #, i.e. id T
             dog (eq t dog-id)
             ;; 5. the switch restores a generic event (no referent at all)
             gen gen-eat (null (cg::referent gen-eat)))))
      (when verbose
        (format t "~&sue eats a pie .    -> ~a~%" (ignore-errors (cg::format-cgraph g1)))
        (format t "~&sue sees the dog .  -> ~a~%" (ignore-errors (cg::format-cgraph g2)))
        (format t "~&one Sue across both: ~a   two eatings distinct: ~a~%"
                (and sue1 sue2 (eq sue1 sue2))
                (and eat1-ind eat3-ind (not (cg::same-individual-p eat1-ind eat3-ind))))
        (format t "~&relative: ~d MAN concept(s), ~d SEE event(s) with ~d distinct id(s)~%"
                (length men) (length sees) (length (remove-duplicates see-ids)))
        (format t "~&*individuate-events* NIL -> generic event: ~a~%"
                (and gen-eat (null (cg::referent gen-eat)))))
      (format t "~&extract-identity-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
      pass)))

;;; The registry is session-scoped on purpose, so check that the two ways of
;;; scoping it actually scope it -- a registry nothing can clear would make a
;;; test run order-dependent.
(defun extract-identity-scope-test (&optional (verbose t))
  (let* ((outer (with-fresh-identity
                  (let* ((a (%identity-graph "sue eats a pie ."))
                         (b (%identity-graph "sue sees the dog .")))
                    (and a b (eq (%named-individual a "Sue")
                                 (%named-individual b "Sue"))))))
         ;; a private registry must not leak into another
         (isolated
           (let ((one (with-fresh-identity
                        (let ((g (%identity-graph "sue eats a pie .")))
                          (and g (%named-individual g "Sue")))))
                 (two (with-fresh-identity
                        (let ((g (%identity-graph "sue eats a pie .")))
                          (and g (%named-individual g "Sue"))))))
             (and one two (not (eq one two)))))
         ;; reset-name-registry has the same effect within one registry
         (after-reset
           (with-fresh-identity
             (let* ((a (%identity-graph "sue eats a pie ."))
                    (sue-a (and a (%named-individual a "Sue"))))
               (reset-name-registry)
               (let* ((b (%identity-graph "sue eats a pie ."))
                      (sue-b (and b (%named-individual b "Sue"))))
                 (and sue-a sue-b (not (eq sue-a sue-b)))))))
         (pass (and outer isolated after-reset)))
    (when verbose
      (format t "~&shared within a registry: ~a   isolated between: ~a   cleared by reset: ~a~%"
              outer isolated after-reset))
    (format t "~&extract-identity-scope-test: ~:[FAILED <<<~;passed~]~%" pass)
    pass))

(defun extract-identity-headless-suite (&optional (verbose t))
  (let ((a (extract-identity-headless-test verbose))
        (b (extract-identity-scope-test verbose)))
    (and a b)))

(extract-identity-headless-suite)
