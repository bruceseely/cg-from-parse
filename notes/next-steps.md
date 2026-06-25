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

## 5. Modifiers (`getc 'mods`)
Adjective/adverb/PP modifiers (ctree's `MOD:` lines). The reader ignores them
today. Map to attr / manr / loc / ... relations. Add `:mods` to the IR and emit.

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

## 9. Other sentence types
`extract-graph` assumes a declarative clause with a VP. Extend to wh-/yes-no
questions, imperatives, passives, raising (all have integration tests in
parsifal). Negation, quantifiers, numbers, dates → cgraph referents/quantifiers.

## 10. Ergonomic driver
A one-call helper: string → (set up grammar) → parse-sentence → extract-graph,
so callers don't hand-register grammar groups. Possibly per-construction grammar
presets.

## Cross-cutting notes
- Tests load the controlled **test-types** catalog non-destructively via
  `test/test-setup.lisp` (binds `*cgraph-types-directory*`, never repoints the
  `~/.cgraph/types` symlink). PARSIFAL dict has boy/girl/dog/man/person/see/give/
  hit/meet but NOT eat/cake.
- Out-of-ontology lemmas: `*on-missing-type*` (:error / :create / :top).
- Headless run recipe is in each `test/extract-*-headless.lisp` header.
