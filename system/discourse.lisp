;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; discourse.lisp -- what "the girl" refers to.
;;;
;;; A definite NP used to get the bare marker, [GIRL: #], stored as id T. Two
;;; individuals with id T, the same type and no properties are
;;; `individuals-equal', so every "the girl" ever extracted was one girl: the
;;; entity-side version of the [EAT] x8 failure that event individuation fixed
;;; (identity.lisp). Whether "the girl" in sentence 5 is the girl of sentence 1
;;; is a DISCOURSE question, so the answer needs a discourse to be asked in.
;;;
;;; A DISCOURSE is the run of sentences one story is told in: the entities
;;; mentioned so far, most recent first. Its boundaries are EXPLICIT --
;;; `new-discourse' ends the current one, `with-discourse' scopes one -- because
;;; nothing in a sentence says where a story begins. Each cgraph environment
;;; always has a current discourse (like the name registry and the KB), and
;;; `with-fresh-identity' scopes a fresh one along with its fresh registry.
;;;
;;; THE RULES
;;;
;;;  - A definite ("the girl") refers to an entity of the discourse: the most
;;;    recent one of exactly its type; else the ONE whose type is comparable
;;;    with it (one a subtype of the other -- "a woman ... the person"); else,
;;;    with none or several comparable, a NEW entity. Same rule as the name
;;;    registry. It is spoken with a NUMBERED marker, [GIRL: #12], never the
;;;    bare #, so two discourses' girls stay two.
;;;
;;;  - An indefinite ("a girl") asserted at the top level of its sentence opens
;;;    an entity with no individual yet: [GIRL] stays generic, and is shown as
;;;    generic. When a later definite refers to it, the individual is minted
;;;    then and given to BOTH concepts -- the earlier graph is changed in place,
;;;    [GIRL] becoming [GIRL: #12], which is what makes "A girl came in. The
;;;    girl sat down." one girl. (The generator says "the" for any individual,
;;;    so the earlier sentence then regenerates as "The girl came in": a
;;;    first-mention rule there is a generation task, not done here.)
;;;
;;;  - An indefinite that is NOT asserted is no antecedent: inside a negation
;;;    ("the girl does not eat a pie" -- there is no pie) or inside a belief or
;;;    other context ("Greg believes a girl came in"). Hence top level only.
;;;
;;;  - Within one sentence a mention can only refer BACK to earlier sentences:
;;;    "a dog sees the dog" is two dogs, and two definites of one sentence never
;;;    take the same antecedent. What a sentence adds or changes is applied when
;;;    its extraction succeeds, not before, so a failed parse leaves the
;;;    discourse as it was.
;;;
;;;  - A QUERY PATTERN (a question, or anything ASK extracts) only READS: a
;;;    definite takes its antecedent's individual if it has one, else stays
;;;    generic -- the loosest pattern -- and nothing is added or changed.
;;;
;;; NOT HERE: names (the registry decides those; "Sue ... the woman" is not
;;; linked), possessed NPs ("the girl's dog" is identified by its possessor),
;;; plurals and sets, quantified NPs (every / some), and bare nouns.

(in-package :cg-from-parse)

(defvar *resolve-definites* t
  "When true (the default), definite NPs are resolved against the current
discourse and spoken with a numbered marker. NIL restores the bare [X: #].")

(defvar *extract-as-pattern* nil
  "Bound true to extract a QUERY PATTERN: events stay generic and the discourse
is read, never written. A question is extracted this way regardless; ASK binds
it so that a statement it is asked is a pattern too.")

;;; ---------------------------------------------------------------------------
;;; The discourse and its scopes
;;; ---------------------------------------------------------------------------

(defstruct (dentity (:constructor make-dentity (type &key individual concepts)))
  "One entity of a discourse: its TYPE, its INDIVIDUAL (NIL while it has only
been mentioned indefinitely), and the CONCEPTS that mention it."
  type individual concepts)

(defstruct discourse
  (entities '()))   ; most recent first

(defvar *discourse* nil
  "A discourse bound by `with-discourse' / `with-fresh-identity', or NIL, in
which case the current environment's (*DISCOURSES*) is used.")

(defvar *discourses* (make-hash-table :test 'eq)
  "cgraph environment -> its current discourse.")

(defun current-discourse ()
  (or *discourse*
      (gethash cg:*environment* *discourses*)
      (setf (gethash cg:*environment* *discourses*) (make-discourse))))

(defun new-discourse ()
  "End the current discourse: the next \"the girl\" is a new girl unless this
discourse mentions one. Graphs already extracted keep the individuals they have."
  (if *discourse*
      (setf (discourse-entities *discourse*) '())
      (remhash cg:*environment* *discourses*))
  nil)

(defmacro with-discourse (&body body)
  "Run BODY as one discourse of its own, leaving the caller's untouched."
  `(let ((*discourse* (make-discourse)))
     ,@body))

(defun discourse-report (&optional (stream *standard-output*))
  "The current discourse's entities, most recent first -- a REPL convenience."
  (let ((entities (discourse-entities (current-discourse))))
    (format stream "~&discourse: ~d entit~:@p~%" (length entities))
    (dolist (e entities)
      (format stream "  [~a~@[: #~a~]]  ~d mention~:p~%"
              (ignore-errors (cg::label (dentity-type e)))
              (and (dentity-individual e) (cg::id (dentity-individual e)))
              (length (dentity-concepts e))))
    (values)))

;;; ---------------------------------------------------------------------------
;;; Per-sentence state, bound by `with-sentence-discourse' (from ir->cgraph)
;;; ---------------------------------------------------------------------------

(defvar *sentence-discourse* nil
  "While a sentence is extracted: a plist of what it has done to the discourse,
applied by `commit-sentence-discourse' only if extraction succeeds.
  :context  the sentence's top context (where an indefinite is asserted)
  :write    NIL for a query pattern
  :seen     concepts already handled (coreference hands a concept back)
  :claimed  entities this sentence has referred to
  :new      entities this sentence opened, latest first
  :commit   thunks that change earlier graphs and entities")

(defmacro with-sentence-discourse ((context &key write) &body body)
  "Run BODY (one sentence's extraction) with fresh per-sentence state; when it
returns normally, apply what it did to the discourse."
  `(let ((*sentence-discourse* (list :context ,context :write ,write
                                     :seen (make-hash-table :test 'eq)
                                     :claimed '() :new '() :commit '())))
     (multiple-value-prog1 (progn ,@body)
       (commit-sentence-discourse))))

(defun commit-sentence-discourse ()
  (let ((s *sentence-discourse*))
    (when (getf s :write)
      (mapc #'funcall (reverse (getf s :commit)))
      (let* ((d       (current-discourse))
             (claimed (getf s :claimed))
             (rest    (remove-if (lambda (e) (member e claimed)) (discourse-entities d))))
        ;; This sentence's entities become the most recent: what it opened,
        ;; latest first, then what it referred to, then everything else.
        (setf (discourse-entities d)
              (append (getf s :new) claimed rest))))))

;;; ---------------------------------------------------------------------------
;;; Resolution
;;; ---------------------------------------------------------------------------

(defun note-discourse-entity (concept &key determiner plural count quantified possessed)
  "Called for each entity NP the extractor emits. A definite is resolved (and
its referent replaced); an asserted indefinite opens an entity. Everything
outside the rules in the header is left exactly as it was."
  (let ((s *sentence-discourse*))
    (when (and *resolve-definites* s
               (typep concept 'cg::concept)
               (not (gethash concept (getf s :seen)))
               (not (or plural count quantified possessed)))
      (setf (gethash concept (getf s :seen)) t)
      (case determiner
        (:definite   (resolve-definite concept))
        (:indefinite (when (and (getf s :write)
                                (null (cg::referent concept))
                                (eq cg::*context* (getf s :context)))
                       (push (make-dentity (cg::concept-type concept)
                                           :concepts (list concept))
                             (getf *sentence-discourse* :new))))))
    concept))

(defun %antecedent (ctype)
  "The entity of the discourse a definite of CTYPE refers to, or NIL. Entities
already claimed by this sentence are not candidates, nor are stale ones (a type
catalog reloaded since -- see the stale-type guard in identity.lisp)."
  (let* ((claimed    (getf *sentence-discourse* :claimed))
         (candidates (remove-if-not
                      (lambda (e) (and (not (member e claimed))
                                       (%live-type-p (dentity-type e))))
                      (discourse-entities (current-discourse))))
         (exact      (find ctype candidates :key #'dentity-type :test #'eq))
         (near       (remove-if-not (lambda (e) (%types-comparable-p ctype (dentity-type e)))
                                    candidates)))
    (or exact (and (null (rest near)) (first near)))))

(defun resolve-definite (concept)
  (let* ((s      *sentence-discourse*)
         (ctype  (cg::concept-type concept))
         (entity (%antecedent ctype)))
    (cond
      ;; A query pattern reads only: the antecedent's individual, else generic.
      ((not (getf s :write))
       (setf (cg::referent concept)
             (let ((indiv (and entity (dentity-individual entity))))
               (and indiv (cg::make-referent indiv))))
       (when entity (push entity (getf *sentence-discourse* :claimed))))
      ;; Refers back.
      (entity
       (push entity (getf *sentence-discourse* :claimed))
       (let* ((narrower (if (cg::subtype-p ctype (dentity-type entity))
                            ctype
                            (dentity-type entity)))
              (indiv    (or (dentity-individual entity)
                            (cg::make-individual narrower)))
              (opened   (null (dentity-individual entity))))
         (setf (cg::referent concept) (cg::make-referent indiv))
         (push (lambda ()
                 (when opened
                   ;; First definite mention of an indefinite: the earlier
                   ;; concepts get the individual too.
                   (setf (dentity-individual entity) indiv)
                   (dolist (c (dentity-concepts entity))
                     (setf (cg::referent c) (cg::make-referent indiv))))
                 (unless (eq (cg::individual-type indiv) narrower)
                   (setf (cg::individual-type indiv) narrower))
                 (setf (dentity-type entity) narrower)
                 (push concept (dentity-concepts entity)))
               (getf *sentence-discourse* :commit))))
      ;; No antecedent: a new entity, with its own numbered individual.
      (t
       (let ((indiv (cg::make-individual ctype)))
         (setf (cg::referent concept) (cg::make-referent indiv))
         (push (make-dentity ctype :individual indiv :concepts (list concept))
               (getf *sentence-discourse* :new)))))))
