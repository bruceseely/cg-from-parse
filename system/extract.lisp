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
;;;    :tense :past/:present/:future/NIL :aspect :perfect/NIL
;;;    :voice :passive/NIL :clause-type :proposition/:situation/NIL
;;;    :cases (CASE ...) :adjuncts (ADJUNCT ...))
;;;                                              ; :adjuncts = PP adjuncts, each
;;;                                              ; (:prep WORD :relation REL
;;;                                              ; :filler FILLER-IR) -> [PRED]-
;;;                                              ; (rel)->[OBJ] ("in the park" ->
;;;                                              ; (loc)->[PLACE]; "with the
;;;                                              ; telescope" -> (inst)->[OBJECT];
;;;                                              ; "on monday" -> (time)->[PERIOD])
;;;   (:clause-type distinguishes a that-clause complement (:proposition) from an
;;;    infinitival (:situation); NIL for the matrix clause -- see complement-type-for.)
;;; A case (one filled thematic role):
;;;   (:role ROLE-SYMBOL :gfunc GFUNC-SYMBOL :filler FILLER)
;;; A filler is one of:
;;;   (:kind :query   :type-hint cg-type :wh WHO/WHAT/... :node N) ; wh-question gap
;;;   (:kind :named   :name "Mitch" :type-hint cg-type :node N) ; proper name
;;;   (:kind :clause  ...)                       ; nested predicate (recurse)
;;;   (:kind :entity  :node N :lemma LEMMA :words (W..)
;;;                   :determiner :definite/:indefinite/NIL
;;;                   :quantifier :universal/:existential/NIL
;;;                   :number :singular/:plural :count N/NIL :adjs (ADJ..)
;;;                   :poss FILLER-IR/NIL :appos "Name"/NIL :mods (CLAUSE-IR..))
;;;                                              ; an NP; definite -> [X: #],
;;;                                              ; plural -> [X: {*}]; :adjs = adjectives,
;;;                                              ; :poss = genitive possessor (a nested
;;;                                              ; filler IR) -> [POSSESSOR]->(poss)->[X];
;;;                                              ; :appos = apposition name ("the dog,
;;;                                              ; Spot" -> [DOG: Spot]); :mods = relatives
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

(defun predicate-stative-p (pred-concept)
  "True when PRED-CONCEPT's type is a subtype of STATE -- i.e. the predicate is a
state (know/believe), not an act/event. States take expr/stat where acts take
agnt/prop. NIL if the catalog has no STATE type or the concept type is a bare
string (an out-of-ontology lemma)."
  (let ((state (ignore-errors (cg::get-concept-type 'cg::state)))
        (ct    (cg::concept-type pred-concept)))
    (and state (not (typep ct 'string)) (cg::supertype-p ct state))))

(defun case-relation-for (pred-concept role)
  "cgraph relation label for thematic ROLE given the PRED-CONCEPT. A stative
predicate overrides some roles (agt->expr, see *stative-case-role->relation*);
otherwise the default *case-role->relation* applies."
  (or (and (predicate-stative-p pred-concept)
           (cdr (assoc role *stative-case-role->relation*)))
      (case-role->relation role)))

(defparameter *preposition->relation*
  (list ;; locative -> loc (⊤ -> place)
        (cons "IN"     'cg::loc) (cons "ON"      'cg::loc)
        (cons "AT"     'cg::loc) (cons "INSIDE"  'cg::loc)
        (cons "NEAR"   'cg::loc) (cons "BY"      'cg::loc)
        (cons "UNDER"  'cg::loc) (cons "BEHIND"  'cg::loc)
        (cons "OVER"   'cg::loc)
        ;; instrument -> inst (event -> entity). "sees the dog WITH the telescope"
        ;; -- exactly see's canonical (inst)->[OBJECT].
        (cons "WITH"   'cg::inst))
  "Adjunct-preposition word -> cgraph relation. A PP adjunct is a PP the verb did
NOT license as a case (\"the man sees the dog in the park\"); PARSIFAL attaches it
to the clause, and we link its object off the predicate. Locative prepositions map
to `loc' (⊤ -> place); instrumental `with' maps to `inst' (event -> entity). An
adjunct whose preposition isn't mapped here is skipped (with a warning), so an
unknown preposition never aborts the extraction. NB temporal PPs are NOT keyed off
this map alone: a temporal preposition (before/after/...) or a time-NP object
(\"on monday\") routes to `time' via adjunct-relation, which resolves the loc/time
ambiguity of in/on/at by the object's type. (Still future work: `with' comitative
-> an accompaniment relation; the licensed prepositional dative `to' is handled as
a case, not here. `with' is read as instrument, not accompaniment: cgraph
test-types have an `inst' relation but no comitative one.)")

(defun preposition->relation (prep-word)
  "cgraph relation label for an adjunct PREP-WORD (\"in\"/\"on\"/... -> loc), else
NIL. Matched by name so a :parsifal or :cl word symbol both resolve."
  (and prep-word
       (cdr (assoc (string-upcase (string prep-word)) *preposition->relation*
                   :test #'string=))))

(defun complement-relation-for (pred-concept filler)
  "Relation to link PRED-CONCEPT to its clausal complement FILLER. A stative
predicate whose complement is a PROPOSITION (a that-clause) uses `stat'
([STATE]->(stat)->[PROPOSITION], the ontology's canonical form) when the catalog
defines it; otherwise the generic invented *clausal-complement-relation* (prop),
which accepts either a proposition or a situation wrapper. `stat' is guarded to
propositions because its dest is PROPOSITION -- a stative verb with an infinitival
(situation) complement would not type-check against it."
  (or (and (predicate-stative-p pred-concept)
           (not (eq (getf filler :clause-type) :situation))
           (ignore-errors (cg::get-relation-type *stative-complement-relation*))
           *stative-complement-relation*)
      *clausal-complement-relation*))

(defun complement-type-for (ir)
  "cgraph concept type that wraps clause IR as a complement: SITUATION for an
infinitival (:clause-type :situation, an event), else PROPOSITION (a that-clause
or the default). Falls back to PROPOSITION if the catalog lacks a `situation'."
  (or (and (eq (getf ir :clause-type) :situation)
           (ignore-errors (cg::get-concept-type *situation-complement-type*))
           *situation-complement-type*)
      *clausal-complement-type*))

(defparameter *clausal-complement-type* 'cg::proposition
  "Graph-compatible concept type that wraps an embedded clause as a context,
i.e. [PROPOSITION: <inner graph>]. Must be a graph-compatible type. Used for a
THAT-clause (a statement) and as the default; an infinitival uses
*situation-complement-type* (see complement-type-for).")

(defparameter *situation-complement-type* 'cg::situation
  "Graph-compatible concept type wrapping an INFINITIVAL clausal complement as an
event, i.e. [SITUATION: <inner graph>] for \"to go\". A that-clause is a
PROPOSITION (a statement, truth-evaluable); an infinitival is a SITUATION (an
unrealized event). Chosen by the parse's INF-S vs THAT-S feature
(clause-complement-form); falls back to *clausal-complement-type* if the catalog
lacks a graph-compatible `situation'.")

(defparameter *adjective-relation* 'cg::attr
  "Relation linking a noun to an adjective modifier: [NOUN]->(attr)->[ADJ]
(attr: ENTITY -> ATTRIBUTE). Adjectives outside the ATTRIBUTE branch (e.g. an
age word) won't fit and are skipped with a warning; with *on-missing-type*
:create an unknown adjective is created under ATTRIBUTE so it fits.")

(defparameter *possessive-relation* 'cg::poss
  "Relation linking a genitive possessor to the possessed noun:
[POSSESSOR]->(poss)->[POSSESSED] (poss: ANIMATE -> ENTITY). Unlike an adjective
(where the noun is the SOURCE), the POSSESSOR is the source and the possessed head
noun the dest -- so \"the man's dog\" is [MAN: #]->(poss)->[DOG: #], rendered
[DOG: #]<-(poss)<-[MAN: #]. A possessor whose type isn't ANIMATE is skipped with a
warning (like an out-of-branch adjective).")

(defparameter *clausal-complement-relation* 'cg::prop
  "Relation linking a matrix predicate to its clausal complement (a PROPOSITION or
a SITUATION wrapper). Auto-ensured (source ⊤, dest ⊤) if absent, since no standard
case relation accepts a proposition/situation dest. Rebind to taste. This is the
generic fallback; a STATE predicate with a PROPOSITION complement uses
*stative-complement-relation* (`stat') instead (see complement-relation-for).")

(defparameter *stative-complement-relation* 'cg::stat
  "Relation linking a STATE predicate to its clausal-complement proposition:
[STATE]->(stat)->[PROPOSITION]. Preferred over the generic (invented) `prop'
when the predicate's concept type is a subtype of STATE and the catalog defines
`stat' -- this is the ontology's canonical form (cf. KNOW's canonical graph
[KNOW]-(expr)->[ANIMATE] (stat)->[PROPOSITION]). Cognition/communication verbs
that want their own relation would extend this by verb class.")

(defparameter *stative-case-role->relation*
  (list (cons 'pa::agt 'cg::expr))   ; a state's subject EXPERIENCES it
  "Role->relation overrides used when the predicate is a STATE rather than an
ACT. A stative predicate (know/believe) links its subject via `expr'
(experiencer: [STATE]->(expr)->[ANIMATE]), not `agnt' (which requires an ACT
source). Roles absent here fall back to *case-role->relation*.")

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

(defun effective-lemma (node)
  "The lemma an entity NP would use: its case-frame pred if present, else its
head-noun word."
  (or (ignore-errors (pa::getc 'pa::pred node))
      (entity-lemma node)))

(defun filler->ir (filler seen)
  "Convert one case FILLER (a PARSIFAL node) into a filler IR. SEEN is the
recursion path, used to break structural cycles (as ctree1 does)."
  (cond
    ((null filler) (list :kind :empty))
    ;; A proper name ("Mitch", "Chicago"): a named individual [TYPE: Name].
    ((member 'pa::name (ignore-errors (pa::fe filler)))
     (list :kind :named
           :node filler
           :name (proper-name filler)
           :type-hint (proper-name-type filler)
           :words (pa::node-words filler)))
    ;; A bound gap: a trace (control/raising), a relative pronoun (who/that/which
    ;; in a relative), OR a fronted wh-interrogative leaving a trace (object-wh
    ;; questions). A wh gap is the QUERIED element -> a query concept; any other
    ;; gap corefers with its ultimate antecedent (share that concept).
    ((gap-antecedent filler)
     (let* ((b   (gap-antecedent filler))
            (lem (and b (binding-lemma b))))
       (if (wh-lemma-p lem)
           (list :kind :query :node b :type-hint (wh-type lem) :wh lem)
           (list :kind :trace :binding b :lemma lem
                 :words (and b (pa::node-words b))))))
    ;; A wh-interrogative in place (subject-wh question: "who sees ..."). The
    ;; wh word may be the case-frame pred or just the NP's head word.
    ((wh-lemma-p (effective-lemma filler))
     (let ((wh (effective-lemma filler)))
       (list :kind :query :node filler :type-hint (wh-type wh) :wh wh)))
    ;; A personal pronoun ("you" -- esp. the implicit imperative subject -- I,
    ;; he, it, ...): an indexical individual [TYPE: Pronoun].
    ((pronoun-lemma-p (effective-lemma filler))
     (let ((p (effective-lemma filler)))
       (list :kind :named :node filler
             :name (string-capitalize (string p))
             :type-hint (pronoun-type p)
             :words (pa::node-words filler))))
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
              :determiner (np-determiner filler)
              :quantifier (np-quantifier filler)
              :number (np-number filler)
              :count  (np-count filler)
              :adjs  (adjective-lemmas filler)
              :poss  (np-possessor-ir filler seen)
              :appos (np-appos-name filler)
              :mods  (clausal-mods filler seen)))))
    (t
     (list :kind :entity :node filler
           :lemma (entity-lemma filler)
           :words (pa::node-words filler)
           :determiner (np-determiner filler)
           :quantifier (np-quantifier filler)
           :number (np-number filler)
           :count  (np-count filler)
           :adjs  (adjective-lemmas filler)
           :poss  (np-possessor-ir filler seen)
           :appos (np-appos-name filler)
           :mods  (clausal-mods filler seen)))))

(defparameter *wh-type*
  (list (cons "WHO"   'cg::person) (cons "WHOM" 'cg::person)
        (cons "WHAT"  'cg::entity) (cons "WHICH" 'cg::entity)
        (cons "WHERE" 'cg::place))
  "wh-interrogative word -> cgraph concept-type for the queried element.")

(defun wh-type (lemma)
  "Concept-type for a wh-word LEMMA (who->person, what->entity, ...), or NIL."
  (and lemma (cdr (assoc (string-upcase (string lemma)) *wh-type* :test #'string=))))

(defun wh-lemma-p (lemma)
  "True when LEMMA is a wh-interrogative word."
  (and (wh-type lemma) t))

(defparameter *pronoun-type*
  (list (cons "YOU" 'cg::person) (cons "I"  'cg::person) (cons "ME"  'cg::person)
        (cons "HE"  'cg::person) (cons "HIM" 'cg::person)
        (cons "SHE" 'cg::person) (cons "HER" 'cg::person)
        (cons "WE"  'cg::person) (cons "US"  'cg::person)
        (cons "THEY" 'cg::person) (cons "THEM" 'cg::person)
        (cons "IT"  'cg::entity))
  "Personal-pronoun word -> cgraph concept-type. Treated as an indexical
individual ([PERSON: You]); anaphora resolution (he/she/it -> antecedent) is
future work. \"you\" is the implicit subject of imperatives.")

(defun pronoun-type (lemma)
  "Concept-type for a personal-pronoun LEMMA (you/i/he/... -> person, it ->
entity), or NIL."
  (and lemma (cdr (assoc (string-upcase (string lemma)) *pronoun-type* :test #'string=))))

(defun pronoun-lemma-p (lemma)
  "True when LEMMA is a personal pronoun."
  (and (pronoun-type lemma) t))

(defun np-determiner (node)
  "Definiteness of an NP NODE from its features: :definite (the) / :indefinite
(a/an) / NIL (no determiner, e.g. a bare/mass/quantified NP)."
  (let ((fe (ignore-errors (pa::fe node))))
    (cond ((member 'pa::def   fe) :definite)
          ((member 'pa::indef fe) :indefinite)
          (t nil))))

(defun np-number (node)
  "Grammatical number of an NP NODE: :plural (NPL feature) else :singular."
  (if (member 'pa::npl (ignore-errors (pa::fe node))) :plural :singular))

(defun np-count (node)
  "Cardinality of an NP NODE when it leads with a number word (\"three dogs\" ->
3), else NIL. The number word carries its value on its `quant' property."
  (let* ((words (ignore-errors (pa::node-words node)))
         (q     (and words (ignore-errors (get (first words) 'pa::quant)))))
    (when (numberp q) q)))

(defun np-possessor (node)
  "The possessor NP of a genitive NP NODE, or NIL. PARSIFAL parses a genitive
(\"the man's dog\") by making the possessor a POSS-DET determiner of the head NP:
NODE's `det' daughter is a poss-det whose `np' daughter is the possessor poss-np
(\"the man's\" / \"mitch's\" / \"my\"). See parsifal *genitive-rules*."
  (let ((det (ignore-errors (pa::daughter 'pa::det node))))
    (and det
         (member 'pa::poss-det (ignore-errors (pa::fe det)))
         (ignore-errors (pa::daughter 'pa::np det)))))

(defun np-possessor-ir (node seen)
  "Filler IR for NODE's genitive possessor, or NIL. Recurses through filler->ir,
so the possessor gets full treatment -- a common noun (\"the man's\" -> :entity),
a proper name (\"mitch's\" -> :named), or a pronoun."
  (let ((poss (np-possessor node)))
    (and poss (filler->ir poss seen))))

(defun np-appos-name (node)
  "The appositive name of a common-noun NP NODE, e.g. \"the dog , spot\" -> \"Spot\",
else NIL. Apposition attaches the name as a name NP under NODE's `appos' daughter
(see parsifal *apposition-rules*); the head NP keeps its own specific type, and
only the NAME is taken from the appositive -- so \"the dog , spot\" yields
[DOG: Spot] rather than the name marker's broad [ANIMAL: Spot]."
  (let ((appos (ignore-errors (pa::daughter 'pa::appos node))))
    (and appos (proper-name appos))))

(defparameter *proper-noun-type* 'cg::person
  "Default concept-type for a proper name when its markers don't pin one down.")

(defun proper-name (node)
  "The proper-name string of a name NP, e.g. \"Mitch\" (capitalized)."
  (let ((w (ignore-errors (pa::getr 'pa::word (pa::daughter 'pa::noun node)))))
    (when w (string-capitalize (string w)))))

(defun proper-name-type (node)
  "cgraph concept-type for a proper name, from its semantic markers: place ->
place, hanim -> person, anim -> animal, else *proper-noun-type*."
  (let ((markers (ignore-errors (pa::smarkers node))))
    (cond ((member 'pa::place markers) 'cg::place)
          ((member 'pa::hanim markers) 'cg::person)
          ((member 'pa::anim  markers) 'cg::animal)
          (t *proper-noun-type*))))

(defun np-quantifier (node)
  "Quantifier of an NP NODE -- :universal (all/every/each/any) / :existential
(some) / NIL -- from its leading surface word. (Matched by name, since the word
may be a :parsifal or :cl symbol; e.g. \"some\" reads as CL:SOME.)"
  (let* ((words (ignore-errors (pa::node-words node)))
         (w     (and words (string-upcase (string (first words))))))
    (cond ((member w '("ALL" "EVERY" "EACH" "ANY") :test #'string=) :universal)
          ((member w '("SOME")                     :test #'string=) :existential)
          (t nil))))

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

(defparameter *temporal-prepositions*
  '("BEFORE" "AFTER" "DURING" "UNTIL" "SINCE")
  "Prepositions whose PP adjunct is ALWAYS temporal (-> the `time' relation),
whatever the object. The ambiguous locatives in/on/at are temporal only when their
object is a time NP (\"on monday\" vs \"on the mat\") -- see adjunct-relation.")

(defun temporal-preposition-p (prep)
  "True when PREP is a dedicated temporal preposition (before/after/...)."
  (and prep (member (string-upcase (string prep)) *temporal-prepositions*
                    :test #'string=)
       t))

(defun np-temporal-p (np)
  "True when NP is a time expression -- PARSIFAL's `time' feature (monday, ...) --
so a PP over it is temporal even under an ambiguous preposition (\"on monday\")."
  (and np (member 'pa::time (ignore-errors (pa::fe np))) t))

(defun adjunct-relation (prep obj)
  "cgraph relation label for a PP adjunct, resolving the loc/time ambiguity of
in/on/at by the object's type: a temporal preposition OR a time-NP object -> the
`time' relation (situation -> time-period); otherwise the preposition's default
(locatives -> loc, `with' -> inst). NIL if the preposition isn't mapped at all."
  (cond ((temporal-preposition-p prep) 'cg::time)
        ((np-temporal-p obj)           'cg::time)
        (t (preposition->relation prep))))

(defun pp-adjunct-ir (pp seen)
  "Adjunct IR for a surface PP node -- (:prep WORD :relation REL :filler OBJECT-IR)
-- or NIL if the PP has no object NP. The relation is resolved from the preposition
AND the object's type (see adjunct-relation). The object recurses through
filler->ir, so it gets full NP treatment (determiner, adjectives, apposition, ...)."
  (let ((prep (ignore-errors (pa::word (pa::daughter 'pa::prep pp))))
        (obj  (ignore-errors (pa::daughter 'pa::np pp))))
    (when (and prep obj)
      (list :prep prep
            :relation (adjunct-relation prep obj)
            :filler (filler->ir obj seen)))))

(defun clause-adjuncts (node seen)
  "Adjunct IRs for clause NODE's surface PP adjuncts. These are the `pp' daughters
PARSIFAL attached to the clause because the verb did NOT license them as a case
(a licensed PP -- e.g. give's `to' -- fills a case instead and never surfaces as a
clause pp daughter). Each becomes [PRED]-(rel)->[OBJ] in emit-clause."
  (loop for pp in (ignore-errors (pa::daughters 'pa::pp node))
        for ir = (pp-adjunct-ir pp seen)
        when ir collect ir))

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

(defun clause-verb-node (node)
  "The verb leaf for a clause / VP / comp-np NODE (descends VP, then S, then a
comp-np's embedded S), or NIL."
  (cond ((null node) nil)
        ((ignore-errors (pa::daughter 'pa::verb node)))
        ((ignore-errors (pa::daughter 'pa::vp node))
         (clause-verb-node (pa::daughter 'pa::vp node)))
        ((ignore-errors (pa::daughter 'pa::s node))
         (clause-verb-node (pa::daughter 'pa::s node)))
        (t nil)))

(defun clause-voice (node)
  "cgraph voice keyword for clause NODE: :passive when its verb is a passive
participle, else NIL (active is the cgraph default)."
  (let ((verb (clause-verb-node node)))
    (when (and verb (member 'pa::passive (pa::fe verb))) :passive)))

(defun clause-complement-form (node)
  "Semantic form of a clausal complement NODE, for choosing its wrapper concept
type (see complement-type-for): :situation for an INFINITIVAL complement (INF-S,
an unrealized event -- \"to go\"), :proposition for a THAT-clause (THAT-S, a
statement), or NIL when NODE isn't a recognizable complement clause (e.g. the
matrix clause). The INF-S/THAT-S feature sits on the embedded S under a COMP-NP,
so descend to it (or use NODE itself if it already is the COMP-S)."
  (let* ((s     (if (member 'pa::comp-s (pa::fe node))
                    node
                    (ignore-errors (pa::daughter 'pa::s node))))
         (feats (and s (pa::fe s))))
    (cond ((member 'pa::inf-s  feats) :situation)
          ((member 'pa::that-s feats) :proposition)
          (t nil))))

(defun clause->ir (node seen)
  "Convert a predicate-bearing NODE into a clause IR."
  (let ((spec (cadr (pa::getc 'pa::spec node))))
    (list :kind   :clause
          :pred   (pa::getc 'pa::pred node)
          :spec   spec
          :tense  (spec-tense spec)
          :aspect (spec-aspect spec)
          :voice  (clause-voice node)
          :clause-type (clause-complement-form node)
          :node   node
          :cases  (loop for (cname filler gfunc) in (reverse (pa::getc 'pa::cases node))
                        collect (list :role cname :gfunc gfunc
                                      :filler (filler->ir filler seen)))
          :adjuncts (clause-adjuncts node seen))))

(defun parse->ir (node)
  "Build a clause IR from a PARSIFAL parse NODE. Flushes the open frame first
(like ctree) so the matrix predicate's filled cases are visible."
  (pa::closeframe pa::openframe)
  (let ((clause (clause-node-of node)))
    (clause->ir clause (list clause))))

;;; ===========================================================================
;;; Emission layer:  IR  ->  cgraph
;;; ===========================================================================

(defun build-referent (ctype &key definite plural count)
  "Referent for a concept of CTYPE, by precedence:
  plural/count -> a generic set ([X: {*}]), with COUNT stored as a :measure
                  (cgraph's formatter doesn't render set cardinality, so the
                  count is captured but not shown -- like tense/voice);
  definite      -> a definite individual ([X: #]);
  else          -> NIL (bare [X])."
  (cond
    ((or plural count)
     (let ((ref (cg::make-referent (cg::build-set-from-specs (list "*") ctype))))
       (when count (setf (getf (cg::properties ref) :measure) count))
       ref))
    (definite (cg::make-referent (cg::make-individual ctype nil :id t)))
    (t nil)))

(defun concept-of (ctype &key definite plural count)
  "A concept of CTYPE with the referent implied by definite/plural/count."
  (cg::make-concept ctype (build-referent ctype :definite definite
                                                :plural plural :count count)))

(defun concept-for (lemma required-type &key definite plural count)
  "A cgraph concept whose type is named LEMMA. REQUIRED-TYPE is the concept-type
the surrounding relation demands (used only under *on-missing-type* :create to
place a newly-created type so arcs type-check). DEFINITE/PLURAL/COUNT pick the
referent (see build-referent)."
  ;; The parser emits lemmas as :parsifal symbols (e.g. pa::eat) while cgraph
  ;; types live in :cg; normalize by name so the lookup crosses packages.
  (let* ((name  (intern (string-upcase (string lemma)) :cg))
         (ctype (ignore-errors (cg::get-concept-type name))))
    (flet ((mk (ct) (concept-of ct :definite definite :plural plural :count count)))
      (cond
        (ctype (mk ctype))
        ((eq *on-missing-type* :create)
         ;; NB: make-concept-type must get a SYMBOL here -- the STRING method
         ;; (types.lisp) forces the supertype to WORD and ignores supertypes-list;
         ;; the symbol method honors it.
         (cg::make-concept-type name
                                :supertypes-list (list (type-label required-type)))
         (mk (cg::get-concept-type name)))
        ((eq *on-missing-type* :top)
         (mk cg::*concept-type-top*))
        (t
         (error "cg-from-parse: no concept type for lemma ~a ~
                 (and *on-missing-type* is ~s)" lemma *on-missing-type*))))))

(defun type-label (type-designator)
  "A symbol/label suitable for make-concept-type :supertypes-list, given a
concept-type object or a symbol."
  (if (symbolp type-designator) type-designator (cg::label type-designator)))

(defvar *node->concept*)    ; PARSIFAL node -> emitted cgraph concept, for this extraction
(defvar *node->corefvar*)   ; PARSIFAL node -> coreference label (for cross-context coref)
(defvar *corefvar-counter*) ; allocates fresh coreference labels

(defun concept-for-node (node lemma required-type &key definite plural count)
  "Concept for PARSIFAL NODE, reusing the one already emitted for it if present
-- this is how coreference is realized: a trace and its antecedent map to the
SAME node, hence the same concept (one node, several arcs). Otherwise create a
concept of type LEMMA (referent per definite/plural/count), register it under
NODE, and return it."
  (or (and node (gethash node *node->concept*))
      (let ((concept (concept-for lemma required-type
                                  :definite definite :plural plural :count count)))
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
    (let ((tense (getf ir :tense)) (aspect (getf ir :aspect)) (voice (getf ir :voice)))
      (when tense  (setf (cg::concept-tense pred-concept) tense))
      (when aspect (setf (cg::concept-aspect pred-concept) aspect))
      (when voice  (setf (cg::concept-voice pred-concept) voice)))
    (dolist (case (getf ir :cases))
      (let* ((role      (getf case :role))
             (filler    (getf case :filler))
             (clausal   (eq (getf filler :kind) :clause))
             (rel-label (if clausal
                            (complement-relation-for pred-concept filler)
                            (case-relation-for pred-concept role))))
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
    ;; PP adjuncts (unlicensed PPs PARSIFAL hung on the clause): [PRED]-(rel)->[OBJ],
    ;; rel from the preposition ("in the park" -> loc). After the cases, so the
    ;; predicate concept already exists.
    (dolist (adj (getf ir :adjuncts))
      (emit-adjunct pred-concept adj))
    pred-concept))

(defun emit-adjunct (pred-concept adj)
  "Emit [PRED]-(REL)->[OBJ] for a PP adjunct ADJ (:prep + :relation + :filler); REL
was resolved from the preposition and the object type (adjunct-relation). Skips
(with a warning) an unmapped preposition or an object whose type doesn't fit the
relation's dest, so an adjunct never aborts the extraction."
  (let ((rel-label (getf adj :relation)))
    (if (null rel-label)
        (warn "cg-from-parse: PP adjunct (~a ...) dropped: no relation mapped for preposition"
              (getf adj :prep))
        (let* ((relation    (cg::make-relation rel-label))
               (dest-type   (cg::dest-type (cg::relation-type relation)))
               (obj-concept (emit-filler (getf adj :filler) dest-type)))
          (when obj-concept
            (if (arc-dest-ok-p obj-concept relation)
                (progn (cg::add-arc-into-relation pred-concept relation)
                       (cg::set-arc-from-relation relation obj-concept))
                (warn "cg-from-parse: PP adjunct [~a] not linked via (~a): type ~a doesn't fit dest ~a"
                      (getf adj :prep) rel-label
                      (cg::label (cg::concept-type obj-concept)) (cg::label dest-type))))))))

(defun arc-dest-ok-p (concept relation)
  "Would CONCEPT satisfy RELATION's out-arc (dest) type? Mirrors the test in
set-arc-from-relation, so we can decide before mutating the graph."
  (let ((ct (cg::concept-type concept))
        (dt (cg::dest-type (cg::relation-type relation))))
    (or (typep ct 'string)
        (cg::supertype-p ct dt)
        (equal ct (cg::label dt)))))

(defun query-concept (node type-hint)
  "A query (requested) concept for a wh-question gap: a generic concept of
TYPE-HINT carrying a fresh query variable (*x), so the result is a runnable
query pattern (cgraph's query engine solves for the variable). Reused per node."
  (or (and node (gethash node *node->concept*))
      (let* ((ctype   (or (ignore-errors (cg::get-concept-type type-hint))
                          cg::*concept-type-top*))
             (concept (cg::make-concept ctype nil)))
        (cg::set-variable concept (intern (format nil "X~d" (incf *corefvar-counter*)) :cg))
        (when node (setf (gethash node *node->concept*) concept))
        concept)))

(defun named-concept (type-hint name node)
  "A named-individual concept, [TYPE-HINT: NAME] -- reusing NODE's already-emitted
concept if present (coreference)."
  (or (and node (gethash node *node->concept*))
      (let* ((ctype   (or (ignore-errors (cg::get-concept-type type-hint))
                          cg::*concept-type-top*))
             (indiv   (cg::make-individual ctype (list :name name)))
             (concept (cg::make-concept ctype (cg::make-referent indiv))))
        (when node (setf (gethash node *node->concept*) concept))
        concept)))

(defun emit-filler (filler required-type)
  "Emit a filler IR; return its concept (or NIL for fillers we don't realize as
concepts, e.g. an unbound trace)."
  (case (getf filler :kind)
    ;; A clausal complement is embedded as a context concept -- a PROPOSITION
    ;; (that-clause) or a SITUATION (infinitival), per its :clause-type.
    (:clause  (emit-clause-as-complement filler))
    (:query   (query-concept (getf filler :node) (getf filler :type-hint)))
    (:named   (named-concept (getf filler :type-hint) (getf filler :name)
                             (getf filler :node)))
    (:entity  (let ((concept (concept-for-node (getf filler :node)
                                               (getf filler :lemma) required-type
                                               :definite (eq (getf filler :determiner) :definite)
                                               :plural   (eq (getf filler :number) :plural)
                                               :count    (getf filler :count))))
                ;; Apposition ("the dog , spot"): keep the head's specific type but
                ;; make it a NAMED individual -- [DOG: Spot], not [DOG: #]. The name
                ;; comes from the appositive; the type stays the head noun's.
                (let ((appos (getf filler :appos)))
                  (when appos
                    (setf (cg::referent concept)
                          (cg::make-referent
                           (cg::make-individual (cg::concept-type concept)
                                                (list :name appos))))))
                ;; Quantifier (all/some...): stored on the concept, like
                ;; tense/voice -- not shown in linear form, used by the realizer.
                (let ((q (getf filler :quantifier)))
                  (when q (setf (cg::concept-quantifier concept) q)))
                ;; Adjective modifiers: [NOUN]->(attr)->[ADJ].
                (dolist (adj (getf filler :adjs))
                  (emit-modifier concept *adjective-relation* adj))
                ;; Genitive possessor: [POSSESSOR]->(poss)->[NOUN] (possessor
                ;; is the ANIMATE source, this noun the dest).
                (let ((poss (getf filler :poss)))
                  (when poss (emit-possessor concept poss)))
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

(defun emit-possessor (possessed-concept poss-ir)
  "Emit [POSSESSOR]->(poss)->[POSSESSED-CONCEPT] for a genitive: the possessor
(POSS-IR, already a filler IR) is the ANIMATE source, the possessed head noun the
ENTITY dest. Reverse of emit-modifier (there the noun is the source). Skips with a
warning when the possessor's type doesn't fit `poss''s source, so a non-animate
possessor never aborts the extraction."
  (let* ((relation   (cg::make-relation *possessive-relation*))
         (src-type   (car (cg::source-types (cg::relation-type relation))))
         (poss-concept (emit-filler poss-ir src-type)))
    (when poss-concept
      (if (arc-source-ok-p poss-concept relation)
          (progn (cg::add-arc-into-relation poss-concept relation)
                 (cg::set-arc-from-relation relation possessed-concept))
          (warn "cg-from-parse: possessor [~a] not linked via (~a): type ~a doesn't fit source ~a"
                (or (getf poss-ir :lemma) (getf poss-ir :name)) *possessive-relation*
                (cg::label (cg::concept-type poss-concept))
                (and src-type (cg::label src-type)))))))

(defun arc-source-ok-p (concept relation)
  "Would CONCEPT satisfy one of RELATION's in-arc (source) types? Mirrors
arc-dest-ok-p but for the source side (add-arc-into-relation)."
  (let ((ct (cg::concept-type concept))
        (sts (cg::source-types (cg::relation-type relation))))
    (or (typep ct 'string)
        (some (lambda (st) (or (cg::supertype-p ct st)
                               (equal ct (cg::label st))))
              sts))))

(defun emit-clause-as-complement (ir)
  "Embed clause IR as a graph-referent concept -- [PROPOSITION: <inner graph>] for
a that-clause, [SITUATION: <inner graph>] for an infinitival, per IR's
:clause-type (see complement-type-for). The inner graph is built in a CHILD
context (mirroring cgraph's own read-graph-referent-concept), so any coreference
from inside back out to an enclosing concept must cross the context boundary
(handled in emit-trace)."
  (let* ((cg::*context*          (cg::make-context cg::*context*))
         (cg::*concepts-in-graph* (list))
         (pred-concept (emit-clause ir))
         (graph        (cg::make-cgraph pred-concept cg::*context*))
         (referent     (cg::make-referent graph nil)))
    (cg::make-concept (cg::get-concept-type (complement-type-for ir)) referent)))

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
  "Make sure *clausal-complement-relation* exists, creating it if the catalog
lacks it. Source ⊤, dest ⊤ -- dest is the top type (not proposition) so the one
generic relation accepts BOTH complement wrappers, a PROPOSITION (that-clause)
and a SITUATION (infinitival). Returns the label."
  (let ((label *clausal-complement-relation*))
    (unless (ignore-errors (cg::get-relation-type label))
      (cg::make-relation-type label
                              :source-types (list cg::*concept-type-top*)
                              :dest-type    cg::*concept-type-top*
                              :description  "clausal complement: proposition/situation (cg-from-parse)"))
    label))

(defun ir->cgraph (ir)
  "Emit a complete cgraph graph from clause IR, in a fresh child context."
  ;; Start each extraction with clean cgraph coreference + variable caches:
  ;; both are process-global in cgraph (*coref-labels* / *variables*), so a label
  ;; like X1 registered by a previous extraction would otherwise leak in and make
  ;; a new X1 resolve to the stale concept -- corrupting the *x/?x coref split.
  (cg::initialize-coreferences)
  (cg::initialize-variables)
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
