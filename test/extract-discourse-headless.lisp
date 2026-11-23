;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; DISCOURSE -- what "the girl" refers to (system/discourse.lisp).
;;;
;;;   1. a definite carries over between sentences: "the dog" twice is one dog,
;;;      with a NUMBERED marker
;;;   2. an indefinite links back: "a girl ... the girl" is one girl, and the
;;;      earlier graph's [GIRL] gets the individual too -- and is still said
;;;      "a girl"
;;;   3. within one sentence a mention only refers back: "a dog sees the dog"
;;;      is two dogs
;;;   4. an indefinite under negation is no antecedent
;;;   5. a comparable type resolves and narrows; the type never widens;
;;;      incomparable types are two entities
;;;   6. a question only reads: no new entities, earlier graphs untouched
;;;   7. new-discourse / with-discourse are boundaries
;;;   8. *resolve-definites* NIL gives back the bare [X: #]
;;;
;;;   sbcl --non-interactive --disable-debugger \
;;;     --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
;;;     --load test/extract-discourse-headless.lisp

(in-package :cg-from-parse)

(load (merge-pathnames "test-setup.lisp"
                       (or *load-truename* *compile-file-truename*)))
(setup-test-cgraph)

(defun %dgraph (sentence)
  "SENTENCE extracted through the driver (as TELL would), or NIL."
  (handler-bind ((warning #'muffle-warning))
    (ignore-errors (parse-and-extract sentence))))

(defun %dconcept (graph label &optional (n 0))
  "The Nth concept in GRAPH, nested contexts included, whose type is LABEL."
  (let ((found '()))
    (labels ((walk (g)
               (dolist (node (cg::nodes g))
                 (when (typep node 'cg::concept)
                   (when (string-equal label (string (cg::label (cg::concept-type node))))
                     (push node found))
                   (let ((inner (ignore-errors (cg::content (cg::referent node)))))
                     (when (typep inner 'cg::graph) (walk inner)))))))
      (when graph (walk graph)))
    (nth n (reverse found))))

(defun %dindiv (concept)
  "The individual CONCEPT's referent holds, or NIL."
  (let ((c (and concept (cg::referent concept) (cg::content (cg::referent concept)))))
    (and (typep c 'cg::individual) c)))

(defun %ty (label) (cg::get-concept-type (intern label :cg)))

(defun %definite (label)
  "A definite of type LABEL put through the discourse as a one-word sentence."
  (let ((c (cg::make-concept (%ty label) nil)))
    (with-sentence-discourse (cg::*context* :write t)
      (note-discourse-entity c :determiner :definite))
    c))

(defun extract-discourse-headless-test (&optional (verbose t))
  (let ((checks '()))
    (flet ((check (label ok) (push (cons label (and ok t)) checks)))
      (with-fresh-identity
        ;; 1 + 2
        (let* ((g1    (%dgraph "a girl eats a pie ."))
               (girl1 (%dconcept g1 "GIRL"))
               (generic-at-first (and girl1 (null (cg::referent girl1))))
               (g2    (%dgraph "the girl sees the dog ."))
               (g3    (%dgraph "the dog sees the man .")))
          (check "an indefinite stays generic until referred to" generic-at-first)
          (check "a girl ... the girl: one girl, the earlier graph changed"
                 (and (%dindiv girl1) (eq (%dindiv girl1) (%dindiv (%dconcept g2 "GIRL")))))
          (check "the linked first mention still says \"a girl\""
                 (and (equal (ignore-errors (say-graph g1)) "A girl eats a pie.")
                      (equal (ignore-errors (say-graph g2)) "The girl sees the dog.")))
          (check "a referred-to entity is numbered"
                 (numberp (cg::id (%dindiv (%dconcept g2 "GIRL")))))
          (check "the dog twice: one dog"
                 (and (%dindiv (%dconcept g2 "DOG"))
                      (eq (%dindiv (%dconcept g2 "DOG")) (%dindiv (%dconcept g3 "DOG")))))
          ;; 3
          (let ((g (%dgraph "a dog sees the dog .")))
            (check "a dog sees the dog: two dogs"
                   (and g (null (cg::referent (%dconcept g "DOG" 0)))
                        (eq (%dindiv (%dconcept g "DOG" 1)) (%dindiv (%dconcept g3 "DOG"))))))
          ;; 4 -- in a discourse of its own: here the asserted pie of the first
          ;; sentence would rightly be "the pie"
          (with-discourse
            (let* ((neg (%dgraph "the girl does not eat a pie ."))
                   (pie (%dgraph "the man eats the pie .")))
              (check "a denied pie is no antecedent"
                     (and neg pie (null (cg::referent (%dconcept neg "PIE")))
                          (%dindiv (%dconcept pie "PIE"))
                          (= 1 (length (dentity-concepts
                                        (find (%dindiv (%dconcept pie "PIE"))
                                              (discourse-entities (current-discourse))
                                              :key #'dentity-individual))))))))
          ;; 6
          (let* ((n-before (length (discourse-entities (current-discourse))))
                 (q (%dgraph "does the man see the boy ?")))
            (check "a question reads the discourse: the man is the man"
                   (and q (eq (%dindiv (%dconcept q "MAN")) (%dindiv (%dconcept g3 "MAN")))))
            (check "a question adds nothing: the unknown boy stays generic"
                   (and q (null (cg::referent (%dconcept q "BOY")))
                        (= n-before (length (discourse-entities (current-discourse)))))))
          (let* ((g   (%dgraph "a boy eats a pie ."))
                 (boy (%dconcept g "BOY")))
            (%dgraph "does the boy see the dog ?")
            (check "a question changes no earlier graph" (and boy (null (cg::referent boy)))))
          ))
      ;; 7 -- from a clean start, so the only dog is the one under test
      (with-fresh-identity
        (flet ((the-dog () (%dindiv (%dconcept (%dgraph "the dog sees the man .") "DOG"))))
          (let* ((dog   (the-dog))
                 (inner (with-discourse (the-dog))))
            (check "with-discourse: a different dog, the outer one kept"
                   (and dog inner (not (eq inner dog)) (eq dog (the-dog))))
            (new-discourse)
            (check "new-discourse: a different dog"
                   (let ((d (the-dog))) (and d (not (eq d dog))))))))
      ;; 5: on the discourse directly -- whether the dictionary has `woman'
      ;; and `person' is not what is tested
      (with-fresh-identity
        (let ((w (%definite "WOMAN")) (p (%definite "PERSON")))
          (check "the woman ... the person: one, still WOMAN"
                 (and (%dindiv w) (eq (%dindiv w) (%dindiv p))
                      (eq (cg::individual-type (%dindiv w)) (%ty "WOMAN"))))))
      (with-fresh-identity
        (let ((p (%definite "PERSON")) (w (%definite "WOMAN")))
          (check "the person ... the woman: one, narrowed to WOMAN"
                 (and (%dindiv p) (eq (%dindiv p) (%dindiv w))
                      (eq (cg::individual-type (%dindiv p)) (%ty "WOMAN"))))))
      (with-fresh-identity
        (let ((w (%definite "WOMAN")) (m (%definite "MAN")))
          (check "the woman ... the man: two"
                 (and (%dindiv w) (%dindiv m) (not (eq (%dindiv w) (%dindiv m)))))))
      ;; 8
      (with-fresh-identity
        (let* ((*resolve-definites* nil)
               (g (%dgraph "the dog sees the man .")))
          (check "*resolve-definites* NIL: the bare #"
                 (and g (eq t (cg::id (%dindiv (%dconcept g "DOG")))))))))
    (setf checks (reverse checks))
    (when verbose
      (dolist (c checks)
        (format t "~&  ~:[FAIL <<<~;pass~]  ~a~%" (cdr c) (car c))))
    (let ((pass (every #'cdr checks)))
      (format t "~&extract-discourse-headless-test: ~:[FAILED <<<~;passed~]~%" pass)
      pass)))

(extract-discourse-headless-test)
