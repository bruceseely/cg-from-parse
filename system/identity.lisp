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

(defparameter *individuate-events*  t
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
  "(TYPE-LABEL . NAME) -> individual, for as long as the knowledge base lives.
NIL until first use; `name-registry' creates it. Deliberately NOT rebound by
`extract-graph' -- outliving a single extraction is the entire point.")

(defun name-registry ()
  "The live registry, created on first use."
  (or *name-registry*
      (setf *name-registry* (make-hash-table :test 'equal))))

(defun reset-name-registry ()
  "Forget every name. The next mention of Sue starts a new person.
Call between independent knowledge bases; NOT between sentences of one."
  (setf *name-registry* nil))

(defmacro with-fresh-identity (&body body)
  "Run BODY over a private registry, leaving the caller's untouched. For tests
and for extracting a corpus that must not share individuals with another."
  `(let ((*name-registry* (make-hash-table :test 'equal)))
     ,@body))

(defun name-registry-key (ctype name)
  ;; Keyed by TYPE as well as name, so [DOG: Spot] and [PERSON: Spot] stay two
  ;; individuals. The limitation this accepts: "Sue" typed PERSON in one
  ;; sentence and WOMAN in another is two individuals, because unifying them
  ;; means picking the more specific type and re-typing the earlier concept --
  ;; lattice work, and a decision about which mention wins. Not attempted here.
  (cons (ignore-errors (cg::label ctype)) name))

(defun registered-individual (ctype name)
  "THE individual of CTYPE named NAME -- the same object every time, so that
`same-individual-p' holds across sentences and a join has something to unify on.
Minted and recorded on first mention.

STALE-TYPE GUARD. The registry outlives an extraction on purpose, which means it
can also outlive a type-catalog reload: `reset-cgraph' / `initialize-cgraph'
build FRESH concept-type objects, and an individual minted before one still
points at the old instance. The key survives (it is the type's LABEL, a symbol),
so the entry would be found and handed back holding a dead type -- the classic
stale-reference bug in this codebase. Cheap and self-healing: if the cached
individual's type is no longer the live object, mint a new one. Sameness is lost
across a catalog reload, which is correct -- that is a different knowledge base."
  (let* ((key   (name-registry-key ctype name))
         (table (name-registry))
         (found (gethash key table)))
    (if (and found (eq (ignore-errors (cg::individual-type found)) ctype))
        found
        (setf (gethash key table)
              (cg::make-individual ctype (list :name name))))))

(defun name-registry-report (&optional (stream *standard-output*))
  "What the registry is holding -- one line per named individual. A REPL
convenience for asking who the knowledge base thinks exists."
  (let ((table *name-registry*))
    (if (null table)
        (format stream "~&name registry: empty~%")
        (progn
          (format stream "~&name registry: ~d individual~:p~%"
                  (hash-table-count table))
          (let ((rows '()))
            (maphash (lambda (key indiv)
                       (push (list (car key) (cdr key)
                                   (ignore-errors (cg::id indiv)))
                             rows))
                     table)
            (dolist (row (sort rows #'string<
                               :key (lambda (r) (format nil "~a ~a" (first r) (second r)))))
              (format stream "  [~a: ~a]  #~a~%"
                      (first row) (second row) (third row))))))
    (values)))
