;;; -*- Mode: LISP; Syntax: Common-lisp; Base: 10; Lowercase: Yes -*-
;;;
;;; extract.lisp — turn PARSIFAL parse products into conceptual graphs.
;;;
;;; Pipeline, split at a clean seam (an intermediate representation, the IR):
;;;
;;;     PARSIFAL parse  --parse->ir-->  IR  --ir->cgraph-->  cgraph graph
;;;
;;;   * parse->ir  reads PARSIFAL case frames (the predicate-argument
;;;     structure that `ctree' prints) into a Lisp-data IR. Parser side.
;;;   * ir->cgraph emits cgraph concepts/relations from the IR. cgraph side.
;;;
;;; The IR seam lets each half be developed and tested independently: the
;;; emitter against hand-written IR (no live parser), the reader against a
;;; live parse.
;;;
;;; Boundary conventions: this is glue that intentionally reaches into both
;;; systems' internals. Neither :parsifal nor :conceptual-graphs exports a
;;; broad API, so symbols are referenced with the double-colon qualifier
;;; (pa::… / cg::…). Every crossing is therefore explicit.
;;;
;;; --- IR shape --------------------------------------------------------------
;;;
;;; A clause / predicate:
;;;   (:kind :clause :pred LEMMA :spec SPEC-NODE-OR-NIL :node PA-NODE
;;;    :tense :past/:present/:future/NIL :aspect :perfect/NIL :cases (CASE ...))
;;; A case (one filled thematic role):
;;;   (:role ROLE-SYMBOL :gfunc GFUNC-SYMBOL :filler FILLER)
;;; A filler is one of:
;;;   (:kind :clause  ...)                       ; nested predicate (recurse)
;;;   (:kind :entity  :node N :lemma LEMMA :words (W..) :adjs (ADJ..)
;;;                   :mods (CLAUSE-IR..))       ; an NP; :adjs = adjectives,
;;;                                              ; :mods = relative clauses
;;;   (:kind :trace   :binding PA-NODE :words (W..)) ; a bound trace (coref)
;;;   (:kind :backref :lemma LEMMA)               ; structural cycle, not recursed
;;;   (:kind :empty)                              ; nil filler

(in-package :cg-from-parse)

;;; ===========================================================================
;;; Mapping tables / policy
;;; ===========================================================================

(defparameter *case-role->relation*
  (list (cons 'pa::agt    'cg::agnt)   ; agent     -> agnt  (ACT -> ANIMATE)
        (cons 'pa::neut   'cg::obj)    ; neutral   -> obj   (ACT -> ENTITY)
        (cons 'pa::dat    'cg::rcpt)   ; dative    -> rcpt  (ACT -> ANIMATE)
        (cons 'pa::loc    'cg::loc)    ; location  -> loc   (⊤   -> PLACE)
        (cons 'pa::manner 'cg::manr))  ; manner    -> manr  (ACT -> MANNER)
  "PARSIFAL thematic case roles (in :parsifal) mapped to cgraph relation labels
(in :conceptual-graphs). Each relation is emitted as [PRED]->(rel)->[filler], so
the predicate (an ACT/EVENT) is the SOURCE -- only relations whose source accepts
an act belong here (that excludes poss/from/goal, whose sources are
animate/entity/state). agt/neut/dat are exercised by the test verbs; the
prepositional dative (give's `to' PP) also fills DAT. loc/manr are wired and
correct but need a verb that licenses them (or surface-tree PP-adjunct handling,
see notes/next-steps.md) to surface -- PP adjuncts are NOT in the case frame.")

(defparameter *predicate-root* 'cg::act
  "Concept-type a predicate (verb) lemma is placed under when it must be
created (see *on-missing-type*). All case relations require an ACT source.")

(defparameter *on-missing-type* :error
  "Policy when a lemma has no concept type in the loaded catalog:
  :error  — signal (default; safest, keeps extraction faithful to the ontology)
  :create — make the type as a subtype of the contextually-required type
            (predicate -> *predicate-root*; filler -> the relation's dest-type)
  :top    — use the top type (⊤) as a catch-all")

(defun case-role->relation (role)
  "cgraph relation label for PARSIFAL thematic ROLE, or NIL if unmapped."
  (cdr (assoc role *case-role->relation*)))

(defparameter *clausal-complement-type* 'cg::proposition
  "Graph-compatible concept type that wraps an embedded clause as a context,
i.e. [PROPOSITION: <inner graph>]. Must be a graph-compatible type.")

(defparameter *adjective-relation* 'cg::attr
  "Relation linking a noun to an adjective modifier: [NOUN]->(attr)->[ADJ]
(attr: ENTITY -> ATTRIBUTE). Adjectives outside the ATTRIBUTE branch (e.g. an
age word) won't fit and are skipped with a warning; with *on-missing-type*
:create an unknown adjective is created under ATTRIBUTE so it fits.")

(defparameter *clausal-complement-relation* 'cg::prop
  "Relation linking a matrix predicate to its clausal-complement proposition.
Auto-ensured (source ⊤, dest *clausal-complement-type*) if absent, since no
standard case relation accepts a proposition dest. Rebind to taste.")

;;; ===========================================================================
;;; Reading layer:  PARSIFAL parse  ->  IR
;;; ===========================================================================
;;; Mirrors parsifal's own ctree1 traversal (util.lisp): pred + spec + the
;;; filled cases, recursing into clausal fillers, with traces shown by their
;;; binding. See parsifal GLOSSARY "Following a parse: stree and ctree".

(defun clause-node-of (node)
  "Find the case-frame-bearing node to start from. Given a root S, descend to
its VP (where the predicate's frame lives); given a VP/clause already, use it."
  (cond ((null node)
         (error "cg-from-parse: no parse to extract from (node is NIL)"))
        ((pa::getc 'pa::pred node) node)
        ((pa::daughter 'pa::vp node))
        (t node)))

(defun entity-lemma (np-node)
  "Head-noun root word of an NP filler (e.g. BOY), falling back to the first
surface word when the head can't be located."
  (let ((h (ignore-errors (pa::head np-node))))
    (or (and h (pa::word h))
        (first (pa::node-words np-node)))))

(defun filler->ir (filler seen)
  "Convert one case FILLER (a PARSIFAL node) into a filler IR. SEEN is the
recursion path, used to break structural cycles (as ctree1 does)."
  (cond
    ((null filler) (list :kind :empty))
    ;; A bound gap: a trace (control/raising) OR an overt bound relative pronoun
    ;; (who/that/which, the subject of a subject relative). Either corefers with
    ;; its ultimate antecedent (gap -> who -> head noun); share that concept.
    ((gap-antecedent filler)
     (let ((b (gap-antecedent filler)))
       (list :kind :trace
             :binding b
             :lemma   (and b (binding-lemma b))
             :words   (and b (pa::node-words b)))))
    ;; Both clauses and NPs carry a `pred' in their case frame (an NP's pred is
    ;; its head noun -- cf. ctree's "PRED: BOY"). Distinguish by filled cases:
    ;; a predicate clause has them, a plain NP does not.
    ((pa::getc 'pa::pred filler)
     (cond
       ((member filler seen :test #'equal)
        (list :kind :backref :node filler :lemma (pa::getc 'pa::pred filler)))
       ((pa::getc 'pa::cases filler)
        (clause->ir filler (cons filler seen)))
       (t
        (list :kind :entity :node filler
              :lemma (pa::getc 'pa::pred filler)
              :words (pa::node-words filler)
              :adjs  (adjective-lemmas filler)
              :mods  (clausal-mods filler seen)))))
    (t
     (list :kind :entity :node filler
           :lemma (entity-lemma filler)
           :words (pa::node-words filler)
           :adjs  (adjective-lemmas filler)
           :mods  (clausal-mods filler seen)))))

(defun adjective-lemmas (np-node)
  "Adjective words attached to NP-NODE as surface `adj' daughters (e.g. BIG in
\"the big dog\"). PP adjuncts are NOT here -- PARSIFAL drops a verb-unlicensed
PP entirely, and a licensed one is already a case; see notes/next-steps.md."
  (loop for adj in (ignore-errors (pa::daughters 'pa::adj np-node))
        for w = (and adj (ignore-errors (pa::getr 'pa::word adj)))
        when w collect w))

(defun binding-lemma (node)
  "Head-noun lemma of a trace's antecedent NODE (its case-frame pred, else its
head noun)."
  (or (ignore-errors (pa::getc 'pa::pred node))
      (entity-lemma node)))

(defun node-binding (node)
  "The antecedent stored in NODE's `binding' REGISTER, or NIL. (Use this, not
the `binding' function, which only chases trace/* nodes and returns an overt
relative pronoun like `who' unchanged -- whereas `who' carries its head NP in
the register.)"
  (and node (ignore-errors (pa::getr 'pa::binding node))))

(defun ultimate-antecedent (node)
  "Follow the binding-register chain (trace -> wh-comp -> head NP) to the final
antecedent node, so coreference targets the real head, not an intermediate."
  (let ((b (node-binding node)))
    (if (and b (not (eq b node)))
        (ultimate-antecedent b)
        node)))

(defun gap-antecedent (node)
  "If NODE is a bound gap -- a trace, or a relative pronoun bound to an
antecedent -- return its ultimate antecedent; otherwise NIL."
  (when node
    (let ((b (node-binding node)))
      (when (and b (not (eq b node)))
        (ultimate-antecedent node)))))

(defun clausal-mods (node seen)
  "Clause IRs for NODE's clausal modifiers -- i.e. relative clauses, which live
in the head noun's case-frame `mods' (each mod's VP carries the relative
predicate and a trace bound back to NODE). Non-clausal mods (adjectives, ...)
are skipped for now."
  (loop for mod in (pa::getc 'pa::mods node)
        for clause = (and mod (clause-node-of mod))
        when (and clause
                  (pa::getc 'pa::pred clause)
                  (pa::getc 'pa::cases clause))
          collect (clause->ir clause (cons node seen))))

(defun spec-tense (spec-node)
  "cgraph tense keyword (:past / :present / :future) from a PARSIFAL aux SPEC
node's features, or NIL (e.g. a tenseless infinitive)."
  (when spec-node
    (let ((fe (pa::fe spec-node)))
      (cond ((member 'pa::past   fe) :past)
            ((member 'pa::future fe) :future)
            ((member 'pa::pres   fe) :present)
            (t nil)))))

(defun spec-aspect (spec-node)
  "cgraph aspect keyword (:perfect) from a PARSIFAL aux SPEC node, or NIL.
(Progressive isn't distinguished in the base feature set yet.)"
  (when (and spec-node (member 'pa::perf (pa::fe spec-node)))
    :perfect))

(defun clause->ir (node seen)
  "Convert a predicate-bearing NODE into a clause IR."
  (let ((spec (cadr (pa::getc 'pa::spec node))))
    (list :kind   :clause
          :pred   (pa::getc 'pa::pred node)
          :spec   spec
          :tense  (spec-tense spec)
          :aspect (spec-aspect spec)
          :node   node
          :cases  (loop for (cname filler gfunc) in (reverse (pa::getc 'pa::cases node))
                        collect (list :role cname :gfunc gfunc
                                      :filler (filler->ir filler seen))))))

(defun parse->ir (node)
  "Build a clause IR from a PARSIFAL parse NODE. Flushes the open frame first
(like ctree) so the matrix predicate's filled cases are visible."
  (pa::closeframe pa::openframe)
  (let ((clause (clause-node-of node)))
    (clause->ir clause (list clause))))

;;; ===========================================================================
;;; Emission layer:  IR  ->  cgraph
;;; ===========================================================================

(defun concept-for (lemma required-type)
  "A cgraph concept whose type is named LEMMA. REQUIRED-TYPE is the
concept-type the surrounding relation demands (used only under
*on-missing-type* :create to place a newly-created type so arcs type-check)."
  ;; The parser emits lemmas as :parsifal symbols (e.g. pa::eat) while cgraph
  ;; types live in :cg; normalize by name so the lookup crosses packages.
  (let* ((name  (intern (string-upcase (string lemma)) :cg))
         (ctype (ignore-errors (cg::get-concept-type name))))
    (cond
      (ctype (cg::make-concept ctype nil))
      ((eq *on-missing-type* :create)
       ;; NB: make-concept-type must get a SYMBOL here -- the STRING method
       ;; (types.lisp) forces the supertype to WORD and ignores supertypes-list;
       ;; the symbol method honors it.
       (cg::make-concept-type name
                              :supertypes-list (list (type-label required-type)))
       (cg::make-concept (cg::get-concept-type name) nil))
      ((eq *on-missing-type* :top)
       (cg::make-concept cg::*concept-type-top* nil))
      (t
       (error "cg-from-parse: no concept type for lemma ~a ~
               (and *on-missing-type* is ~s)" lemma *on-missing-type*)))))

(defun type-label (type-designator)
  "A symbol/label suitable for make-concept-type :supertypes-list, given a
concept-type object or a symbol."
  (if (symbolp type-designator) type-designator (cg::label type-designator)))

(defvar *node->concept*)    ; PARSIFAL node -> emitted cgraph concept, for this extraction
(defvar *node->corefvar*)   ; PARSIFAL node -> coreference label (for cross-context coref)
(defvar *corefvar-counter*) ; allocates fresh coreference labels

(defun concept-for-node (node lemma required-type)
  "Concept for PARSIFAL NODE, reusing the one already emitted for it if present
-- this is how coreference is realized: a trace and its antecedent map to the
SAME node, hence the same concept (one node, several arcs). Otherwise create a
concept of type LEMMA, register it under NODE, and return it."
  (or (and node (gethash node *node->concept*))
      (let ((concept (concept-for lemma required-type)))
        (when node (setf (gethash node *node->concept*) concept))
        concept)))

(defun emit-clause (ir)
  "Emit clause IR into the current context; return its predicate concept.
Builds  [PRED]->(rel)->[FILLER]  for each mapped, filled case. A clausal-
complement filler is embedded as a proposition and linked via the proposition
relation instead of the case's entity-typed relation."
  (let ((pred-concept (concept-for-node (getf ir :node) (getf ir :pred) *predicate-root*)))
    ;; Carry tense/aspect onto the predicate concept (not shown by the linear
    ;; formatter, but stored for the realizer / queries).
    (let ((tense (getf ir :tense)) (aspect (getf ir :aspect)))
      (when tense  (setf (cg::concept-tense pred-concept) tense))
      (when aspect (setf (cg::concept-aspect pred-concept) aspect)))
    (dolist (case (getf ir :cases))
      (let* ((role      (getf case :role))
             (filler    (getf case :filler))
             (clausal   (eq (getf filler :kind) :clause))
             (rel-label (if clausal
                            *clausal-complement-relation*
                            (case-role->relation role))))
        (when rel-label
          (let* ((relation  (cg::make-relation rel-label))
                 (dest-type (cg::dest-type (cg::relation-type relation)))
                 (filler-concept (emit-filler filler dest-type)))
            (when filler-concept
              (cond
                ((arc-dest-ok-p filler-concept relation)
                 (cg::add-arc-into-relation pred-concept relation)
                 (cg::set-arc-from-relation relation filler-concept))
                ;; Shouldn't normally happen now (clausal fillers go via the
                ;; proposition relation); keep a graceful skip just in case.
                (clausal
                 (warn "cg-from-parse: clausal complement [~a] not linked from [~a] via (~a)"
                       (getf filler :pred) (getf ir :pred) rel-label))
                ;; A real type mismatch on an entity/trace filler: let cgraph
                ;; raise its detailed diagnostic.
                (t
                 (cg::add-arc-into-relation pred-concept relation)
                 (cg::set-arc-from-relation relation filler-concept))))))))
    pred-concept))

(defun arc-dest-ok-p (concept relation)
  "Would CONCEPT satisfy RELATION's out-arc (dest) type? Mirrors the test in
set-arc-from-relation, so we can decide before mutating the graph."
  (let ((ct (cg::concept-type concept))
        (dt (cg::dest-type (cg::relation-type relation))))
    (or (typep ct 'string)
        (cg::supertype-p ct dt)
        (equal ct (cg::label dt)))))

(defun emit-filler (filler required-type)
  "Emit a filler IR; return its concept (or NIL for fillers we don't realize as
concepts, e.g. an unbound trace)."
  (case (getf filler :kind)
    ;; A clausal complement is embedded as a proposition context concept.
    (:clause  (emit-clause-as-proposition filler))
    (:entity  (let ((concept (concept-for-node (getf filler :node)
                                               (getf filler :lemma) required-type)))
                ;; Adjective modifiers: [NOUN]->(attr)->[ADJ].
                (dolist (adj (getf filler :adjs))
                  (emit-modifier concept *adjective-relation* adj))
                ;; Relative clauses: assert each as a predicate in THIS context.
                ;; The head's concept is already registered, so the relative gap
                ;; (a trace bound back to the head) shares it -- one node, the
                ;; matrix arc plus the relative clause's arc.
                (dolist (mod (getf filler :mods))
                  (emit-clause mod))
                concept))
    (:trace   (emit-trace filler required-type))
    ;; Backref (structural cycle): reuse the concept already emitted for the node.
    (:backref (and (getf filler :node) (gethash (getf filler :node) *node->concept*)))
    (t nil)))

(defun emit-modifier (source-concept rel-label lemma)
  "Emit [SOURCE]->(REL)->[LEMMA] -- e.g. a noun's adjective. Skips (with a
warning) when LEMMA's type doesn't fit the relation's dest, so an out-of-branch
modifier never aborts the extraction."
  (let* ((relation   (cg::make-relation rel-label))
         (dest-type  (cg::dest-type (cg::relation-type relation)))
         (mod-concept (concept-for lemma dest-type)))
    (if (arc-dest-ok-p mod-concept relation)
        (progn (cg::add-arc-into-relation source-concept relation)
               (cg::set-arc-from-relation relation mod-concept))
        (warn "cg-from-parse: modifier [~a] not linked via (~a): type ~a doesn't fit dest ~a"
              lemma rel-label
              (cg::label (cg::concept-type mod-concept)) (cg::label dest-type)))))

(defun emit-clause-as-proposition (ir)
  "Embed clause IR as a graph-referent concept [PROPOSITION: <inner graph>].
The inner graph is built in a CHILD context (mirroring cgraph's own
read-graph-referent-concept), so any coreference from inside back out to an
enclosing concept must cross the context boundary (handled in emit-trace)."
  (let* ((cg::*context*          (cg::make-context cg::*context*))
         (cg::*concepts-in-graph* (list))
         (pred-concept (emit-clause ir))
         (graph        (cg::make-cgraph pred-concept cg::*context*))
         (referent     (cg::make-referent graph nil)))
    (cg::make-concept (cg::get-concept-type *clausal-complement-type*) referent)))

(defun emit-trace (filler required-type)
  "Realize a trace (control/raising gap) as coreference with its antecedent.
Same context  -> the SAME concept node (shared-node identity coreference).
Crossing into an embedded context -> a fresh bound occurrence (?x) linked to
the antecedent's defining variable (*x), since cgraph forbids a shared node
across contexts."
  (let ((b (getf filler :binding)))
    (when b
      (let ((ante (gethash b *node->concept*)))
        (cond
          ;; Antecedent not emitted yet: behave like a normal entity (and
          ;; register it, so a later mention of the same node shares it).
          ((null ante)
           (concept-for-node b (getf filler :lemma) required-type))
          ;; Same context: identity coreference (one node, several arcs).
          ((eq (cg::context ante) cg::*context*)
           ante)
          ;; Cross-context: a coreference label on both occurrences (cgraph's
          ;; register-concept-coreference links the bound one to the antecedent;
          ;; the formatter renders the shared label, e.g. [GIRL:?x1] on each).
          (t
           (let ((occ   (concept-for (getf filler :lemma) required-type))
                 (label (corefvar-for b ante)))
             (cg::register-concept-coreference occ label)
             occ)))))))

(defun corefvar-for (node ante)
  "Coreference label for NODE, allocating one (and registering ANTE as its
defining occurrence) on first use."
  (or (gethash node *node->corefvar*)
      (let ((label (intern (format nil "X~d" (incf *corefvar-counter*)) :cg)))
        (setf (gethash node *node->corefvar*) label)
        (cg::register-concept-coreference ante label)   ; defining occurrence
        label)))

(defun ensure-complement-relation ()
  "Make sure *clausal-complement-relation* exists (source ⊤, dest the
complement type), creating it if the catalog lacks it. Returns the label."
  (let ((label *clausal-complement-relation*))
    (unless (ignore-errors (cg::get-relation-type label))
      (cg::make-relation-type label
                              :source-types (list cg::*concept-type-top*)
                              :dest-type    (cg::get-concept-type *clausal-complement-type*)
                              :description  "clausal/propositional complement (cg-from-parse)"))
    label))

(defun ir->cgraph (ir)
  "Emit a complete cgraph graph from clause IR, in a fresh child context."
  (let ((cg::*context*     (cg::make-context cg::*context*))
        (*node->concept*   (make-hash-table :test 'equal))
        (*node->corefvar*  (make-hash-table :test 'equal))
        (*corefvar-counter* 0))
    (ensure-complement-relation)
    (cg::make-cgraph (emit-clause ir) cg::*context*)))

;;; ===========================================================================
;;; Top level
;;; ===========================================================================

(defun extract-graph (&optional (parse pa::c))
  "Extract a conceptual graph from a PARSIFAL parse. PARSE is the root S node
left in the global pa::c by parse-sentence (the default). Returns a cgraph
graph object."
  (ir->cgraph (parse->ir parse)))
