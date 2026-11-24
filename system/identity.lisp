;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; identity.lisp -- saying WHICH thing a graph is about.
;;;
;;; Extraction used to produce graphs that could not be accumulated. Put two
;;; dozen of them in one context and `include-cgraph' collapsed them into one
;;; graph asserting things nobody said -- a single [EAT] with eight agents --
;;; while "Sue" came out as a different person in every sentence
;;; (notes/kb-experiment-findings.md, and 28 distinct ids across 29 mentions in
;;; notes/intake-survey-findings.md).
;;;
;;; Those are ONE failure seen from two ends: nothing in an extracted graph said
;;; which thing it was about. Events over-merged because they were generic;
;;; individuals under-merged because each extraction minted fresh. So there are
;;; two halves here, and they fix different things -- neither does the other's
;;; job:
;;;
;;;   EVENT INDIVIDUATION   fixes [EAT] x8. The join runs include-cgraph ->
;;;                         combine-cgraphs -> graphs-share-concepts-p ->
;;;                         find-automatic-correspondences over COLLECT-NODES.
;;;                         That walks graph nodes and never consults the
;;;                         context, so no amount of cache-wiring reaches it:
;;;                         two referent-less [EAT]s correspond automatically
;;;                         and Sowa's formation rules license the merge. The
;;;                         only fix is for the concepts to stop being generic.
;;;
;;;   THE NAME REGISTRY     fixes 28 Sues. One individual per (type, name) for
;;;                         as long as the knowledge base lives, rather than per
;;;                         extraction.
;;;
;;; WHY A REGISTRY AND NOT cgraph's CONTEXT CACHE. cgraph does have identity
;;; machinery -- `cache-concept' ("cache all concepts for co-reference linking")
;;; and `retrieve-concept', keyed by type + individual / id / properties. It is
;;; unreachable from here for a structural reason: `extract-graph' binds a FRESH
;;; CHILD context per extraction (so embedded contexts nest correctly), and
;;; identity within one sentence is carried by `*node->concept*', a hash table
;;; rebound per extraction and keyed by PARSE NODE. Both are right as they
;;; stand; both are intra-sentence by construction. Making the context outlive
;;; an extraction would change coreference semantics to fix a naming problem.
;;; A registry keyed by (type, name) is the smaller, truer change, and it sits
;;; ABOVE both mechanisms rather than disturbing either.
;;;
;;; (Had we gone through the context, the lookup would have had to be by
;;; PROPERTIES -- `retrieve-concept ctype '(:name "Sue")'. Not by individual:
;;; `individuals-equal' compares the id now, so two Sues with different ids are
;;; correctly not equal and would never match. Recorded because it is the kind
;;; of thing that costs an afternoon to rediscover.)

(in-package :cg-from-parse)

;;; ===========================================================================
;;; Policy
;;; ===========================================================================

(clopt:defoption *individuate-events* t
  :type boolean
  :doc
  "When true (the default), every event concept an extraction emits gets its own
individual referent -- [EAT: #12], `this eating', not eating in general.

This is what an assertion MEANS: \"Sue eats a pie\" reports a particular event,
and a graph that says so can be accumulated without merging into its neighbours.
A generic [EAT] is the right form for a TYPE DEFINITION or a canonical graph --
those come from the ontology, not from here, and are unaffected.

Bound to NIL to get the old generic events back. Kept as a switch, not baked in,
because whether a store individuates on ingest is a policy the same way
`include-cgraph' joining on ingest is a policy, and both deserve to be visible.")

;;; ===========================================================================
;;; Event individuation
;;; ===========================================================================
;;;
;;; The marker has to be a NUMBER, not `#'. cgraph's `make-individual' takes
;;; `:id t' for an unspecified marker, which is what `build-referent' gives a
;;; definite entity -- and TWO of those are `individuals-equal', because the
;;; ids are both T. So [EAT: #] would have individuated nothing; the events
;;; would have gone on merging exactly as before. [EAT: #12] is distinct.

(defun individuate-event (concept)
  "Give CONCEPT its own individual referent, so it names one particular event.
Returns CONCEPT. A no-op when *individuate-events* is off, when CONCEPT is NIL
(a possession clause emits a relation, not a predicate), or when CONCEPT already
has a referent -- which happens when `concept-for-node' hands back a concept
already emitted for the same parse node, i.e. under coreference. Idempotent on
purpose: the caller should not have to know which of those it is holding."
  (when (and concept
             *individuate-events*
             (typep concept 'cg::concept)
             (null (cg::referent concept)))
    (setf (cg::referent concept)
          (cg::make-referent (cg::make-individual (cg::concept-type concept)))))
  concept)

;;; ===========================================================================
;;; The name registry
;;; ===========================================================================

(defvar *name-registry* nil
  "A private registry bound by `with-fresh-identity', or NIL, in which case
each cgraph environment has its own (*NAME-REGISTRIES*). Deliberately NOT
rebound by `extract-graph' -- outliving a single extraction is the entire
point.")

(defvar *name-registries* (make-hash-table :test 'eq)
  "cgraph environment -> its registry: NAME -> the individuals of that name, for
as long as that knowledge base lives. Per environment because individuals are:
one shared table would hand environment A's Sue to environment B, and the
stale-type guard in `registered-individual' would then replace A's entry with
B's, so alternating between the two would lose sameness in both.")

(defun %current-name-registry ()
  "The registry in force, or NIL when none has been made yet."
  (or *name-registry*
      (gethash cg:*environment* *name-registries*)))

(defun name-registry ()
  "The live registry, created on first use."
  (or (%current-name-registry)
      (setf (gethash cg:*environment* *name-registries*)
            (make-hash-table :test 'equal))))

(defun reset-name-registry ()
  "Forget every name. The next mention of Sue starts a new person.
Call between independent knowledge bases; NOT between sentences of one.
Inside `with-fresh-identity' it clears that private registry."
  (if *name-registry*
      (clrhash *name-registry*)
      (remhash cg:*environment* *name-registries*))
  nil)

(defmacro with-fresh-identity (&body body)
  "Run BODY over a private registry and a discourse of its own (discourse.lisp),
leaving the caller's untouched. For tests and for extracting a corpus that must
not share individuals with another."
  `(let ((*name-registry* (make-hash-table :test 'equal))
         (*discourse*     (make-discourse)))
     ,@body))

;;; Keyed by NAME alone; the type is settled by the lattice, not by the key.
;;;
;;; It used to be keyed by (TYPE . NAME), which kept [DOG: Spot] and
;;; [PERSON: Spot] apart -- right -- but also split [PLACE: Boston] from
;;; [CITY: Boston], and [PERSON: Sue] from [WOMAN: Sue]. A name whose kind is
;;; learned later (a dictionary entry gains `city', a later sentence says
;;; "woman") then named two individuals, and nothing in the output showed it.
;;;
;;; The rule now: a mention is the individual of that name whose type it is
;;; COMPARABLE with -- one type a subtype of the other. If the mention is the
;;; more specific, the individual's type narrows to it. That needs no re-typing
;;; of concepts already emitted: [PLACE: Boston] holding an individual of type
;;; CITY conforms (the individual's type is under the concept's), so earlier
;;; graphs stay correct as they stand. Incomparable types are still different
;;; individuals, so Spot the dog and Spot the person stay two.
;;;
;;; What it does not do:
;;;  - MEET. [MAN: Dave] and [DOCTOR: Dave] are incomparable, so they stay two,
;;;    though `maximal-common-subtype' could find a type meaning both. Whether
;;;    two incomparable mentions are one individual is a guess the registry
;;;    should not make on a name alone.
;;;  - AMBIGUITY. With [DOG: Spot] and [PERSON: Spot] both registered, a mention
;;;    as [ANIMATE: Spot] is comparable with both. It is not given either: it
;;;    gets an individual of its own (reused by a later mention of exactly that
;;;    type), which is what the old per-type key did.
;;;  - ORDER. Narrowing is first come, first served: PERSON Sue, then MAN Sue,
;;;    then WOMAN Sue gives a man named Sue and a separate woman named Sue.

(defun %live-type-p (ctype)
  "Is CTYPE the concept-type object the catalog would hand out now?"
  (let ((label (ignore-errors (cg::label ctype))))
    (and label (eq (ignore-errors (cg::get-concept-type label)) ctype))))

(defun %types-comparable-p (t1 t2)
  (or (cg::subtype-p t1 t2) (cg::subtype-p t2 t1)))

(defun registered-individual (ctype name)
  "THE individual named NAME that a mention of type CTYPE refers to -- the same
object every time, so that `same-individual-p' holds across sentences and a join
has something to unify on. Minted and recorded on first mention. A mention more
specific than the individual's type narrows it (see the block comment above).

STALE-TYPE GUARD. The registry outlives an extraction on purpose, which means it
can also outlive a type-catalog reload: `reset-cgraph' / `initialize-cgraph'
build FRESH concept-type objects, and an individual minted before one still
points at the old instance. Entries whose individual's type is no longer the live
object are dropped, and a new individual is minted. Sameness is lost across a
catalog reload, which is correct -- that is a different knowledge base."
  (let* ((table   (name-registry))
         (entries (remove-if-not
                   (lambda (indiv)
                     (%live-type-p (ignore-errors (cg::individual-type indiv))))
                   (gethash name table)))
         (exact   (find ctype entries :key #'cg::individual-type :test #'eq))
         (near    (remove-if-not
                   (lambda (indiv)
                     (%types-comparable-p ctype (cg::individual-type indiv)))
                   entries))
         (indiv   (cond (exact)
                        ((null (rest near))
                         (let ((it (first near)))
                           (when (and it (cg::subtype-p ctype (cg::individual-type it)))
                             (setf (cg::individual-type it) ctype))
                           it)))))
    (unless indiv
      (setf indiv (cg::make-individual ctype (list :name name)))
      (push indiv entries))
    (setf (gethash name table) entries)
    indiv))

(defun name-registry-report (&optional (stream *standard-output*))
  "What the registry is holding -- one line per named individual. A REPL
convenience for asking who the knowledge base thinks exists."
  (let ((table (%current-name-registry)))
    (if (null table)
        (format stream "~&name registry: empty~%")
        (progn
          (let ((rows '()))
            (maphash (lambda (name indivs)
                       (dolist (indiv indivs)
                         (push (list (ignore-errors
                                      (cg::label (cg::individual-type indiv)))
                                     name
                                     (ignore-errors (cg::id indiv)))
                               rows)))
                     table)
            (format stream "~&name registry: ~d individual~:p~%" (length rows))
            (dolist (row (sort rows #'string<
                               :key (lambda (r) (format nil "~a ~a" (first r) (second r)))))
              (format stream "  [~a: ~a]  #~a~%"
                      (first row) (second row) (third row))))))
    (values)))
