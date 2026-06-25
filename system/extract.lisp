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
;;;   (:kind :clause :pred LEMMA :spec SPEC-OR-NIL :node PA-NODE
;;;    :cases (CASE ...))
;;; A case (one filled thematic role):
;;;   (:role ROLE-SYMBOL :gfunc GFUNC-SYMBOL :filler FILLER)
;;; A filler is one of:
;;;   (:kind :clause  ...)                       ; nested predicate (recurse)
;;;   (:kind :entity  :lemma LEMMA :words (W..))  ; an NP, head-noun = LEMMA
;;;   (:kind :trace   :binding PA-NODE :words (W..)) ; a bound trace (coref)
;;;   (:kind :backref :lemma LEMMA)               ; structural cycle, not recursed
;;;   (:kind :empty)                              ; nil filler

(in-package :cg-from-parse)

;;; ===========================================================================
;;; Mapping tables / policy
;;; ===========================================================================

(defparameter *case-role->relation*
  (list (cons 'pa::agt  'cg::agnt)    ; agent     -> agnt  (ACT -> ANIMATE)
        (cons 'pa::neut 'cg::obj)     ; neutral   -> obj   (ACT -> ENTITY)
        (cons 'pa::dat  'cg::rcpt))   ; dative    -> rcpt  (ACT -> ANIMATE)
  "PARSIFAL thematic case roles (in :parsifal) mapped to cgraph relation
labels (in :conceptual-graphs). Extend as more roles are handled.")

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
    ;; A trace: a bound gap (control/raising). Carry the antecedent node so the
    ;; emitter can share its concept (coreference), plus its head-noun lemma.
    ((pa::is-any-of filler '(pa::trace pa::*))
     (let ((b (pa::binding filler)))
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
              :words (pa::node-words filler)))))
    (t
     (list :kind :entity :node filler
           :lemma (entity-lemma filler)
           :words (pa::node-words filler)))))

(defun binding-lemma (node)
  "Head-noun lemma of a trace's antecedent NODE (its case-frame pred, else its
head noun)."
  (or (ignore-errors (pa::getc 'pa::pred node))
      (entity-lemma node)))

(defun clause->ir (node seen)
  "Convert a predicate-bearing NODE into a clause IR."
  (list :kind  :clause
        :pred  (pa::getc 'pa::pred node)
        :spec  (cadr (pa::getc 'pa::spec node))
        :node  node
        :cases (loop for (cname filler gfunc) in (reverse (pa::getc 'pa::cases node))
                     collect (list :role cname :gfunc gfunc
                                   :filler (filler->ir filler seen)))))

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

(defvar *node->concept*)   ; PARSIFAL node -> emitted cgraph concept, for this extraction

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
Builds  [PRED]->(rel)->[FILLER]  for each mapped, filled case."
  (let ((pred-concept (concept-for-node (getf ir :node) (getf ir :pred) *predicate-root*)))
    (dolist (case (getf ir :cases))
      (let* ((role      (getf case :role))
             (filler    (getf case :filler))
             (rel-label (case-role->relation role)))
        (when rel-label
          (let* ((relation  (cg::make-relation rel-label))
                 (dest-type (cg::dest-type (cg::relation-type relation)))
                 (filler-concept (emit-filler filler dest-type)))
            (when filler-concept
              (cond
                ((arc-dest-ok-p filler-concept relation)
                 (cg::add-arc-into-relation pred-concept relation)
                 (cg::set-arc-from-relation relation filler-concept))
                ;; A clausal complement (an ACT) doesn't fit an entity-typed
                ;; case such as NEUT->obj. Skip this matrix arc: the embedded
                ;; clause is still emitted and stays connected to the matrix via
                ;; any shared (coreferent) argument. Proper proposition/context
                ;; embedding of the complement is a separate step.
                ((eq (getf filler :kind) :clause)
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
    (:clause  (emit-clause filler))
    (:entity  (concept-for-node (getf filler :node) (getf filler :lemma) required-type))
    ;; Trace: reuse (or create + register) the antecedent's concept -> the
    ;; controlled argument is the SAME concept node as its controller.
    (:trace   (let ((b (getf filler :binding)))
                (and b (concept-for-node b (getf filler :lemma) required-type))))
    ;; Backref (structural cycle): reuse the concept already emitted for the node.
    (:backref (and (getf filler :node) (gethash (getf filler :node) *node->concept*)))
    (t nil)))

(defun ir->cgraph (ir)
  "Emit a complete cgraph graph from clause IR, in a fresh child context."
  (let ((cg::*context*    (cg::make-context cg::*context*))
        (*node->concept*  (make-hash-table :test 'equal)))
    (cg::make-cgraph (emit-clause ir) cg::*context*)))

;;; ===========================================================================
;;; Top level
;;; ===========================================================================

(defun extract-graph (&optional (parse pa::c))
  "Extract a conceptual graph from a PARSIFAL parse. PARSE is the root S node
left in the global pa::c by parse-sentence (the default). Returns a cgraph
graph object."
  (ir->cgraph (parse->ir parse)))
