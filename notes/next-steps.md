# cg-from-parse — next steps

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

Still open under modifiers: adverbs (manr), genitives/possessives (poss), and
adjective-class-specific relations.

## 6. Reconsider the `prop` relation
`*clausal-complement-relation*` defaults to `prop`, auto-invented as
⊤→proposition because no standard case relation accepts a proposition dest.
Options: (a) add a principled relation to the ontology; (b) pick the relation by
verb class — e.g. stative verbs (know/believe) could use the existing `stat`
(state→proposition); cognition/communication verbs may want their own.

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

## 9. Other sentence types  — PARTIAL (passives done)
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
[DOG: {}@3] (count 3 on the referent, rendered as @3). The set's cardinality is
now shown: fixed a cgraph formatter bug where format-referent dropped a set's
:measure (cgraph commit, system/core/referent.lisp + format-measure). See
test/extract-number-headless.lisp.

## 11. Apposition: "the dog, Spot" -> [DOG: Spot]
A standalone named individual only gets the BROAD type from the name's marker
(anim -> [ANIMAL: Fido], never [DOG: Fido]). To get the specific type, the head
noun must supply it via apposition: "the dog, Spot" -> [DOG: Spot]. BLOCKED on
the parser: PARSIFAL has no apposition grammar -- "... the dog , spot ." fails
to parse (NIL) -- so this needs new grammar rules on the PARSIFAL side (parse a
name in apposition to a common-noun NP, keeping the noun's type + the name),
then a small extractor merge (head-noun type + :named name). cgraph already
supports [DOG: Spot]; the gap is purely parser/lexicon (and the name needs a df).

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
