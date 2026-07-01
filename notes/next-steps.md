# cg-from-parse — next steps

> GENITIVES — BLOCKED on the parser (probed 2026-07-01, same class as apposition
> #11). Every genitive form FAILS to parse (NIL) under the full grammar, while
> the matching controls parse:
>   "the man 's dog sees the woman ."  -> NIL   (common-noun genitive, split `'s)
>   "the man's dog sees the woman ."   -> NIL   (joined)
>   "mitch 's dog sees the woman ."    -> NIL   (proper-name genitive)
>   "my dog sees the woman ."          -> NIL   (possessive pronoun)
>   "the dog sees the woman ." / "mitch sees the dog ." -> OK  (controls)
> The pieces exist but don't compose into a possessor+head NP:
>   - `'s is in the dict as (df \'s feats (poss)); the genitive `genlc' case
>     branch in case-frame.lisp is DORMANT (poss-pg-cases is a stubbed NIL no-op).
>   - The only `poss attachment rule is END-OF-NAME in the BUILD-NAME (proper-name)
>     layer: "If 1st is poss then attach 1st to c as poss; label c poss-np."
>     PRONOUN labels a poss-pronoun (my/your/his) as poss-np. BUT no rule ever
>     CONSUMES a poss-np as the specifier of a following head NP, so even "my dog"
>     stalls; and common-noun `'s has no attachment rule outside BUILD-NAME.
> To unblock (PARSIFAL side): add grammar rules that (a) attach `'s to a
> common-noun NP -> poss-np, and (b) take a poss-np as the leading specifier of
> the next NP (like a det), leaving the possessor node reachable. THEN the
> extractor side is small: `poss source is ANIMATE (not ACT), so it's noun->noun,
> NOT the [PRED]->(rel) case path -- emit it like an adjective/mod on the
> possessed noun ([DOG]<-(poss)<-[MAN], or [MAN: #]->(poss)->[DOG]).
>
> NEXT UP: #7 (PROPOSITION vs SITUATION by complement type). With genitives, PP
> adjuncts, adverbs, and apposition all parser-blocked, anaphora deferred, and #6
> now DONE, the remaining actionable ontology/representation work is #7 (choose
> the complement wrapper type by inf-s vs that-s) and #8 (`*x/`?x formatter
> cosmetic). #7 is the more substantive.

Punch list for continuing the PARSIFAL → conceptual-graph extractor. Roughly in
priority order. Current state (2026-06-25): transitive clauses, control
coreference (shared-node + cross-context `?x`), and clausal-complement embedding
as `[PROPOSITION: …]` all work end-to-end. See README for what's done.

## 1. Tense / aspect / modality (`spec`)  — DONE (tense + perfect aspect)
The reader maps the PARSIFAL aux SPEC node's features (pres/past/future, perf)
to `:tense`/`:aspect` on the clause IR (`spec-tense`/`spec-aspect`), and
`emit-clause` sets `concept-tense`/`concept-aspect` on the predicate concept.
NB: the linear formatter does NOT render tense (it's "consumed by the realizer"),
so it's verified via the slot, not the text. "sees" -> :present, "persuaded" ->
:past (see live/coref headless tests).
Still TODO here: progressive aspect (not distinguished in the base feature set),
modal (cgraph has no modal slot — needs a representation), and voice (passive).

## 2. More thematic roles  — PARTIALLY DONE
Map extended with loc→loc and manner→manr (in addition to agt/neut/dat). Also
confirmed the PREPOSITIONAL DATIVE works: "the man gives the book to the woman ."
fills DAT via the `to' PP → same `[GIVE]-(agnt)→[MAN] (obj)→[BOOK] (rcpt)→[WOMAN]`
as the double object (tested).

KEY CONSTRAINTS discovered:
- Every case relation is emitted as [PRED]->(rel)->[filler], so the predicate
  (an ACT/EVENT) is the SOURCE. Only relations whose source accepts an act may be
  added (rules out poss/from/goal — sources animate/entity/state).
- PARSIFAL's full role inventory (dict frequency): neut, time, agt, to, loc,
  poss, dat, from, source, com, with, goal, benef, manner. But the available
  verbs (see/give/persuade) only LICENSE agt/neut/dat (+ give's to→dat). loc/manr
  are wired but won't surface until a verb licenses them.
- **PP adjuncts are NOT in the case frame.** "the man sees the dog in the park"
  drops "in the park" from cases AND mods — it's surface-only (VP daughters).
  So locative/instrument/temporal ADJUNCTS need walking the SURFACE tree, a
  different mechanism than the case-frame reader. That's the real path to more
  roles; fold with #5.

## 3. Ditransitives  — DONE
Works with no code changes. "the man gives the woman the book ." (double object)
parses with the transitive grammar; give fills AGT/DAT/NEUT → agnt/rcpt/obj:
`[GIVE]-(agnt)→[MAN] (obj)→[BOOK] (rcpt)→[WOMAN].` (all in test-types, strict
:error; book added to test-types as object⊓information 2026-06-25).
See test/extract-ditransitive-headless.lisp.
Still open: prepositional dative ("gives the book to the woman") needs the PP
rules + a `to`-PP → rcpt mapping.

## 4. Relative clauses  — DONE (subject relatives in a sentence)
"the boy who sees the dog sees the woman ." ->
`[SEE]-(agnt)→[BOY]←(agnt)←[SEE]→(obj)→[DOG] (obj)→[WOMAN].` -- BOY is one shared
node (matrix agent + relative agent). The relative clause lives in the head
noun's case-frame `mods`; `clausal-mods` reads it, `emit-clause` asserts it in the
same context, and the gap (a trace OR a bound relative pronoun like `who`) shares
the head's concept. Key fix: follow the binding REGISTER (`getr 'binding`) not the
`binding' function (which leaves an overt `who' unchanged); see `node-binding` /
`gap-antecedent`. See test/extract-relative-headless.lisp.
Still open: object relatives inside a full declarative ("...the dog that the man
sees") didn't parse with this grammar union (only as an NP utterance); and the
NP-utterance entry point ("the boy who you met .") isn't wired (extract-graph
expects a clause). Reduced relatives ("the boy you met") untested.

## 5. Modifiers / PP adjuncts  — PARTIALLY DONE (adjectives)
ADJECTIVES work: an adjective attaches to its NP as a surface `adj' daughter;
`adjective-lemmas' reads it (entity IR :adjs) and `emit-modifier' adds
[NOUN]->(attr)->[ADJ]. "the big dog sees the man ." ->
`[SEE]-(agnt)→[DOG]→(attr)→[BIG] (obj)→[MAN].` (BIG :created under ATTRIBUTE).
See test/extract-modifier-headless.lisp. `*adjective-relation*` (default attr);
adjectives outside the ATTRIBUTE branch are skipped with a warning (a smarter
adjective-class -> relation map, e.g. age word -> `age' relation, is future work).

PP ADJUNCTS are NOT extractable as-is: PARSIFAL DROPS a verb-unlicensed PP
("the man sees the dog in the park") entirely -- absent from the case frame AND
the surface tree (VP and NP daughters) -- while a licensed PP is already a case
(give's to->dat). So no extra content to extract. A verb that licenses a loc/inst
PP (e.g. "put", "change") would surface it as a case (loc/manr already mapped),
but none is in test-types.

ADVERBS are BLOCKED (same root cause as PP adjuncts), investigated 2026-06-27:
manner adverbs (quickly/slowly) are NOT in the lexicon (dropped as unknown); and
the deictic adverbs that ARE lexicalized (here/now/there) get DROPPED by a verb
that doesn't license them ("the man sees the dog here ." -> only AGT/NEUT, no
loc/time case, no mod) -- exactly like unlicensed PP adjuncts. So adverb->manr
can't be exercised (the manr/loc relations are already in *case-role->relation*,
so a verb that LICENSES a manner/loc case would map, but none in test-types does).
To unblock: add manner adverbs to the lexicon AND grammar rules that attach
unlicensed adverbial adjuncts (PARSIFAL side), then read them like adjectives.

Still open under modifiers: genitives/possessives (poss) and
adjective-class-specific relations.

## 6. Reconsider the `prop` relation  — DONE (option b: pick by verb class)
The complement relation (and the subject role) are now chosen by the PREDICATE's
semantic class instead of always using the invented `prop'. A STATE predicate
(concept type ⊑ `state') links its clausal complement via the ontology's `stat'
([STATE]->(stat)->[PROPOSITION]) and its subject via `expr' (experiencer,
[STATE]->(expr)->[ANIMATE]) rather than the act-only `agnt'/`prop'. An ACT/EVENT
predicate is unchanged (`agnt' + the invented `prop' fallback). So `know' (the
one STATE verb in BOTH the PARSIFAL dict -- markers (state), via `(jlike know
believe)' -- AND cgraph test-types, `know :supertypes (state)') now yields its
canonical graph:
  "the man knows that the boy sees the dog ." ->
  [KNOW]-(expr)->[MAN: #] (stat)->[PROPOSITION:[SEE]-(agnt)->[BOY: #]
                                                     (obj)->[DOG: #]].
Before this it errored to NIL: [KNOW]-(agnt)-> fails because `agnt' needs an ACT
source and KNOW is a STATE -- the bug that motivated #6. Implementation
(system/extract.lisp): `predicate-stative-p' (concept type ⊑ state),
`*stative-case-role->relation*' (agt->expr), `*stative-complement-relation*'
(stat), `case-relation-for'/`complement-relation-for' consulted in `emit-clause';
both fall back gracefully if the catalog lacks `state'/`stat'. Out-of-ontology
cognition verbs (believe/think, created under ACT via :create) still get
agnt/prop -- fine, since the port's lexicon only marks `know' as an in-ontology
state. See test/extract-stative-headless.lisp.
Still open (folds into #2): a STATE verb's non-clausal object (e.g. "the man
knows the boy", hanim NEUT) would still hit `obj' (ACT-only) -- untested, no
test verb exercises it; a stative NEUT->? mapping is future work if one arises.

## 7. PROPOSITION vs SITUATION for complements
Always `proposition` now. An infinitival "to go" is arguably a SITUATION (an
event); a that-clause a PROPOSITION (a statement). Could choose by complement
type (inf-s vs that-s, available in the parse).

## 8. Coreference rendering `*x` vs `?x` (cosmetic)
The formatter auto-manages `*x` variables (set/unset during its own pass), so a
manually-set defining `*x` gets wiped; both coref occurrences render `?x1`
(cgraph's legacy ?x/?x style). The coref LINK is correct in the object graph.
If a proper `*x` defining marker is wanted in the text, it needs formatter
cooperation (cgraph side).

## 9. Other sentence types  — passives, wh-questions, yes-no questions, imperatives, raising DONE
YES-NO QUESTIONS: same propositional content as the declarative (only the parse
sentence-type feature differs, YNQUEST vs DECL), so extracts to the IDENTICAL
graph -- no new code; semantically the proposition used as a boolean/existence
query. "does the dog see the man ?" == "the dog sees the man ." ->
[SEE]-(agnt)->[DOG: #] (obj)->[MAN: #]. See test/extract-yesno-headless.lisp.
(All the major sentence types are now handled. Remaining: anaphora, adverbs,
genitives, apposition #11, the `*'-set-member reader nicety.)
RAISING: works with NO new code. A raising verb (seem) takes only the clausal
complement (no agent); PARSIFAL resolves the surface subject as the embedded
agent at the case level, so "the boy seems to go ." ->
[SEEM]->(prop)->[PROPOSITION:[GO]->(agnt)->[BOY: #]] falls out of the proposition
machinery. See test/extract-raising-headless.lisp.

IMPERATIVES: PARSIFAL inserts the implicit 2nd-person subject, so the agent
arrives as the pronoun "you". Personal pronouns (pronoun-type: you/i/he/she/we/
they->person, it->entity) are realized as indexical individuals [TYPE: Pronoun]
(reusing :named), e.g. "see the dog ." -> [SEE]-(agnt)->[PERSON: You] (obj)->
[DOG: #]. Anaphora resolution (he/she/it -> antecedent) is future work. See
test/extract-imperative-headless.lisp.

WH-QUESTIONS: a wh-interrogative is the queried element -> a concept of the
wh-type (wh-type: who/whom->person, what/which->entity, where->place) carrying a
query VARIABLE (set-variable), making the graph a runnable query pattern. Two
shapes: subject-wh in place ("who sees...", lemma via effective-lemma) and
fronted-wh leaving a trace ("what does X see", a gap whose binding lemma is the
wh word). IR kind :query; query-concept. NB the lone *x isn't rendered by the
formatter (it's on the concept). who->[PERSON: *x], what->[ENTITY: *x]. See
test/extract-question-headless.lisp. Still open: yes-no questions, imperatives,
raising. (Bare `?' is a no-op in cgraph; `?x' is coreference; queries use *x.)

PASSIVES: PARSIFAL normalizes roles (logical object → NEUT, agent only via a
by-phrase), so roles need no new code; voice is read from the verb's `passive'
feature → `concept-voice :passive' (clause-verb-node / clause-voice). NB:
PARSIFAL's dict has no copular `was'/agentive `by', so only the agentless
participle is available (e.g. "a meeting seems to have been scheduled ." →
embedded SCHEDULE :passive). See test/extract-passive-headless.lisp.
Still open: wh-/yes-no questions, imperatives (implicit "you"), raising.
`extract-graph` still assumes a declarative-style clause with a VP.

DETERMINERS/DEFINITENESS — DONE (definite/indefinite): an NP's DEF/INDEF feature
(np-determiner) → entity IR :determiner; emission gives a definite NP the `#'
referent via definite-concept ([X: #], an individual with id t), indefinite stays
bare. "the man gives the woman a book ." → [MAN: #]/[WOMAN: #], [BOOK]. See
test/extract-determiner-headless.lisp. NB: the space in "[X: #]" depends on
*concise*. 

QUANTIFIERS — DONE (universal/existential): the NP's leading surface word
(np-quantifier) → entity IR :quantifier; emission sets concept-quantifier
(all/every/each/any → :universal, some → :existential). Like tense/voice it's a
stored slot, NOT rendered in linear form (checked via IR + slot, see
test/extract-quantifier-headless.lisp). NB: PARSIFAL's loaded lexicon has
all/some/any but NOT every/each; quant register on the node was empty, so detect
from node-words.

NAMED INDIVIDUALS — DONE: a proper-name NP (the `name' feature) becomes a named
individual [TYPE: Name] -- name from (getr 'word (daughter 'noun np)), type from
semantic markers (smarkers: place->place, hanim->person, anim->animal, else
*proper-noun-type*=person). proper-name / proper-name-type / named-concept; new
IR kind :named. "mitch sees the dog ." -> [SEE]-(agnt)->[PERSON: Mitch]
(obj)->[DOG: #]. (mitch/chicago are in the dict; other names need a df.) See
test/extract-named-headless.lisp.

NUMBERS/PLURALS — DONE: a plural NP (NPL feature, np-number) → a generic set
referent ([X: {*}], renders {}); a leading number (np-count, from the word's
`quant' property) adds the cardinality, stored as a :measure on the referent.
build-referent picks set (plural/count) vs # (definite) vs bare; concept-for /
concept-for-node take &key definite plural count. "three dogs see the man ." ->
[DOG: @3] (count 3 on the referent). The set's cardinality is now shown: fixed a
cgraph formatter bug where format-referent dropped a set's :measure (cgraph
commit, system/core/referent.lisp + format-measure). A generic plural with a
count renders as @N; a set with named members renders [X: {...}@N]. See
test/extract-number-headless.lisp. (Reader detail: build-set-from-specs drops a
generic `*' member, so {Spot, Fido, *}@5 reads/renders as {Spot, Fido}@5 -- the
@5 carries the "5 total" -- a separate reader nicety if the `*' should persist.)

## 11. Apposition: "the dog, Spot" -> [DOG: Spot]
A standalone named individual only gets the BROAD type from the name's marker
(anim -> [ANIMAL: Fido], never [DOG: Fido]). To get the specific type, the head
noun must supply it via apposition: "the dog, Spot" -> [DOG: Spot]. BLOCKED on
the parser: PARSIFAL has no apposition grammar -- "... the dog , spot ." fails
to parse (NIL) -- so this needs new grammar rules on the PARSIFAL side (parse a
name in apposition to a common-noun NP, keeping the noun's type + the name),
then a small extractor merge (head-noun type + :named name). cgraph already
supports [DOG: Spot]; the gap is purely parser/lexicon (and the name needs a df).

## 12. Anaphora (pronoun -> antecedent)  — DEFERRED (2026-06-27)
Pronouns are already RECOGNIZED (pronoun-type -> indexical individuals:
"the man sees him ." -> [SEE]-(agnt)->[MAN: #] (obj)->[PERSON: He];
"... it ." -> [ENTITY: It]). RESOLVING them to antecedents is deferred -- it's a
separate, fuzzy module with no parser support:
- PARSIFAL does NOT bind pronouns: "the man sees him ." -> him has binding=NIL
  (unlike traces/relative-gaps/wh, which are syntactic movement and come bound).
- Reflexives aren't in the lexicon (himself/herself dropped), so even the easy
  syntactically-bound case is unavailable.
- Most anaphora is CROSS-sentence ("...the dog. it runs."), but we parse one
  sentence at a time.
- A real resolver needs gender/number agreement + salience/recency + binding
  theory (e.g. in "the man sees him", `him' must NOT be the man), so a naive
  nearest-NP heuristic is wrong. Not worth a fuzzy, untestable resolver now.
If revisited: scope to a narrow intra-sentence pattern with a permissive binding
("the man thinks he sees the dog"), gated and clearly heuristic; add reflexives
to the lexicon for the clean bound case; or do resolution as a post-pass over a
multi-sentence discourse once that's parsed.

## 10. Ergonomic driver  — DONE
`cg-from-parse:parse-and-extract` (system/driver.lisp): string → cgraph graph.
`ensure-grammar` loads parsifal's clause-grammar.lisp + `load-full-grammar` once
(cached in *grammar-loaded*); one loaded grammar parses every supported
construction (verified across transitive/ditransitive/control/relative/adjective).
`:on-missing` keyword binds *on-missing-type*. Also `sentence->cg-text`. Exported
from the package. See test/extract-driver-headless.lisp.

## Cross-cutting notes
- Tests load the controlled **test-types** catalog non-destructively via
  `test/test-setup.lisp` (binds `*cgraph-types-directory*`, never repoints the
  `~/.cgraph/types` symlink). PARSIFAL dict has boy/girl/dog/man/person/see/give/
  hit/meet but NOT eat/cake.
- Out-of-ontology lemmas: `*on-missing-type*` (:error / :create / :top).
- Headless run recipe is in each `test/extract-*-headless.lisp` header.
