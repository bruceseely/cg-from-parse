# cg-from-parse

Bridge layer that extracts **conceptual graphs** ([`cgraph`](../cgraph)) from
**PARSIFAL** ([`parsifal`](../parsifal)) parse products.

## Why a separate repo

The extraction code conceptually depends on *both* systems, but neither base
system should depend on the other:

```
parsifal   cgraph
    \        /
   cg-from-parse      (depends on both; nothing depends on it)
```

Keeping the glue here leaves `parsifal` and `cgraph` independently loadable,
testable, and releasable, and keeps the dependency graph acyclic. Anyone who
just wants to parse, or just wants conceptual graphs, never pulls in the other.

## Loading

ASDF finds all three systems via the existing source-registry directive
`(:tree "~/repo/")`, which recursively scans `~/repo/` for `.asd` files. As a
sibling repo under `~/repo/`, this system is quickloadable directly:

```lisp
(ql:quickload :cg-from-parse)
```

If ASDF doesn't see it yet, force a rescan with `(asdf:clear-source-registry)`.

## Package boundary

The `:cg-from-parse` package (nickname `:cfp`) uses only `:cl`. Parser and CG
symbols are referenced *qualified* — `pa:…` and `cg:…` — rather than via
`:use`, so every crossing between the two systems is explicit and there are no
symbol conflicts between their large export sets.

## Status

Under construction. The pipeline is split at an intermediate representation (IR):

```
PARSIFAL parse  --parse->ir-->  IR  --ir->cgraph-->  cgraph graph
```

- **`ir->cgraph` (emission): working & tested.** A clause IR emits the right
  conceptual graph, type-checked against the real ontology. E.g. the IR for
  *"the dog eats the cake"* produces `[EAT]-(agnt)→[DOG] (obj)→[CAKE].` See
  `test/extract-emit-headless.lisp`.
- **`parse->ir` (reader): working & validated live.** It mirrors PARSIFAL's own
  `ctree` traversal (pred + filled cases, recursing into clausal fillers, traces
  via their binding). The full pipeline runs end-to-end: parsing
  *"the man sees the dog ."* and extracting yields `[SEE]-(agnt)→[MAN] (obj)→[DOG].`
  See `test/extract-live-headless.lisp`.

Headless tests load the controlled **test-types** catalog (not the user's
customizable cgraph-types) via `test/test-setup.lisp`, which binds
`*cgraph-types-directory*` so it loads in-memory without repointing the user's
`~/.cgraph/types` symlink.

- **Coreference (traces): working.** A PARSIFAL trace (a bound gap in control/
  raising) shares ONE cgraph concept with its antecedent. Parsing
  *"the boy persuaded the girl to go ."* yields
  `[PERSUADE]-(agnt)→[BOY] (rcpt)→[GIRL]←(agnt)←[GO].` — `[GIRL]` is a single
  shared node: the recipient of PERSUADE and the agent of GO. See
  `test/extract-coref-headless.lisp`.
- **Clausal complements: embedded as proposition contexts.** A clause that fills
  a case is wrapped as `[PROPOSITION: <inner graph>]` (a graph-referent concept
  built in a child context) and linked to the matrix predicate via a proposition
  relation (`*clausal-complement-relation*`, default `prop`, auto-created as
  ⊤→proposition since no standard case relation accepts a proposition dest).
  Object control *"the boy persuaded the girl to go ."* now extracts to:
  `[PERSUADE]-(agnt)→[BOY] (prop)→[PROPOSITION:[GO]→(agnt)→[GIRL:?x1]] (rcpt)→[GIRL:?x1].`
  The controlled subject of GO corefers with the matrix object across the context
  boundary: since cgraph forbids a shared node across contexts, it becomes two
  occurrences sharing a coreference label (`?x1`). Knobs:
  `*clausal-complement-type*` (default `proposition`).

- **Relative clauses: working (subject relatives).** *"the boy who sees the dog
  sees the woman ."* → `[SEE]-(agnt)→[BOY]←(agnt)←[SEE]→(obj)→[DOG] (obj)→[WOMAN].`
  The relative clause (from the head noun's case-frame `mods`) is asserted in the
  same context, and its gap (trace or bound relative pronoun) shares the head's
  concept — BOY is one node, agent of both seeings. See
  `test/extract-relative-headless.lisp`.
- **Ditransitives: working, both forms.** Double-object *"the man gives the woman
  the book ."* and prepositional dative *"… gives the book to the woman ."* both
  yield `[GIVE]-(agnt)→[MAN] (obj)→[BOOK] (rcpt)→[WOMAN].` (the `to`-PP fills the
  DAT case). See `test/extract-ditransitive-headless.lisp`.
- **Thematic roles:** `*case-role->relation*` maps agt→agnt, neut→obj, dat→rcpt,
  loc→loc, manr→manr. Each is `[PRED]→(rel)→[filler]` so only act-source relations
  belong. Note: PP *adjuncts* (locatives/instruments) are surface-only (not in the
  case frame), so loc/manr need a verb that licenses them — see `notes/next-steps.md`.
- **Tense/aspect: extracted onto the predicate concept.** The PARSIFAL aux SPEC
  features map to cgraph `concept-tense` (:past/:present/:future) and
  `concept-aspect` (:perfect). "the man sees the dog" → SEE is `:present`; "the
  boy persuaded …" → PERSUADE is `:past`. Note: the *linear* formatter doesn't
  render tense (it's consumed by the realizer), so it lives on the concept slot.

Mapping/policy knobs: `*case-role->relation*` (AGT→agnt, NEUT→obj, DAT→rcpt),
`*on-missing-type*` (`:error`/`:create`/`:top`), `*predicate-root*`.

`cg-from-parse:extract-graph` is the top-level entry: `(extract-graph)` reads
the parse left in `pa::c` by `parse-sentence`.

## Tests

```lisp
(asdf:test-system :cg-from-parse)   ; or
(cg-from-parse::test-all t)
```
