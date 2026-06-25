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

## 2. More thematic roles
`*case-role->relation*` currently maps only AGT→agnt, NEUT→obj, DAT→rcpt. Learn
PARSIFAL's full role inventory (from case.l / defs.l markersets) and extend:
instrument→inst, location→loc, etc. Unmapped roles are silently dropped today.

## 3. Ditransitives
"give" → agnt/obj/rcpt. Grammar: `*ditransitive-*` / two-object rule groups.
Likely works structurally already; needs a test (e.g. "the man gives the dog the
cake") and confirmation the three cases map cleanly.

## 4. Relative clauses
e.g. "the dog that the man sees" — a trace (object/subject gap) bound to the head
noun. Extraction entry point is an NP, not a clause, so `extract-graph` /
`clause-node-of` need an NP-rooted path. The gap coref is same-context (shared
node) in most cases. Grammar: `*relative-clause-rules*` etc.

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
