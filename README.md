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

## Usage

One call, English to conceptual graph (with a running cgraph in your session):

```lisp
(cg-from-parse:parse-and-extract "the man gives the woman the book .")
;; => #<GRAPH [GIVE]-(agnt)→[MAN] (obj)→[BOOK] (rcpt)→[WOMAN].>

(cg-from-parse:sentence->cg-text "the boy persuaded the girl to go ."
                                 :on-missing :create)
;; => "[PERSUADE]-(agnt)→[BOY] (prop)→[PROPOSITION:[GO]→(agnt)→[GIRL:?x1]] (rcpt)→[GIRL:?x1]."
```

`parse-and-extract` self-initializes on first use — it brings up cgraph (loads
your `~/.cgraph/types` catalog + a `*context*`) and loads + registers PARSIFAL's
full grammar, each a no-op if already set up — then parses and extracts, with no
per-construction rule-group selection. So it works right after
`(ql:quickload :cg-from-parse)` and won't disturb a running session. The
`:on-missing` keyword binds `*on-missing-type*` (`:error` default / `:create` /
`:top`) for out-of-ontology words.

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
- **Raising: working.** A raising verb (`seem`) takes only the clausal complement
  (no agent of its own), with the surface subject semantically the embedded
  agent. *"the boy seems to go ."* → `[SEEM]→(prop)→[PROPOSITION:[GO]→(agnt)→[BOY: #]].`
  PARSIFAL resolves it at the case level, so it falls out of the proposition
  machinery with no new code. See `test/extract-raising-headless.lisp`.
- **Imperatives: working.** PARSIFAL supplies the implicit 2nd-person subject, so
  the agent comes through as "you", realized as an indexical individual
  `[PERSON: You]`. *"see the dog ."* → `[SEE]-(agnt)→[PERSON: You] (obj)→[DOG: #].`
  (Personal pronouns generally map to indexical individuals; anaphora resolution
  is future work.) See `test/extract-imperative-headless.lisp`.
- **Yes-no questions: working.** A yes-no question has the same propositional
  content as the declarative — it asks whether that proposition holds — so it
  extracts to the identical graph (semantically, that proposition used as a
  boolean/existence query). *"does the dog see the man ?"* ≡ *"the dog sees the
  man ."* → `[SEE]-(agnt)→[DOG: #] (obj)→[MAN: #].` See
  `test/extract-yesno-headless.lisp`.
- **wh-questions: extracted as queries.** A wh-interrogative (in-place subject
  "who", or a fronted "what" leaving a trace) is the queried element — a concept
  of the wh-type (who→person, what→entity, …) carrying a query variable (`*x`),
  so the result is a runnable query pattern for cgraph's query engine.
  *"who sees the dog ?"* → `[SEE]-(agnt)→[PERSON: *x] (obj)→[DOG: #]`. (The lone
  `*x` isn't shown by the formatter; it's on the concept.) See
  `test/extract-question-headless.lisp`.
- **Adjective modifiers: working.** *"the big dog sees the man ."* →
  `[SEE]-(agnt)→[DOG]→(attr)→[BIG] (obj)→[MAN].` An adjective (a surface `adj`
  daughter of its NP) becomes `[NOUN]→(attr)→[ADJ]`. See
  `test/extract-modifier-headless.lisp`. (PP adjuncts are a different story:
  PARSIFAL drops a verb-unlicensed PP entirely, and a licensed one is already a
  case — so they yield no extra extractable content; see `notes/next-steps.md`.)
- **Thematic roles:** `*case-role->relation*` maps agt→agnt, neut→obj, dat→rcpt,
  loc→loc, manr→manr. Each is `[PRED]→(rel)→[filler]` so only act-source relations
  belong. Note: PP *adjuncts* (locatives/instruments) are surface-only (not in the
  case frame), so loc/manr need a verb that licenses them — see `notes/next-steps.md`.
- **Named individuals: extracted.** A proper name becomes a named individual
  `[TYPE: Name]` — type from the name's semantic markers (hanim→person,
  place→place, anim→animal, else `*proper-noun-type*`). *"mitch sees the dog ."*
  → `[SEE]-(agnt)→[PERSON: Mitch] (obj)→[DOG: #].` See
  `test/extract-named-headless.lisp`.
- **Number/plural: extracted onto the referent.** A plural NP becomes a generic
  set, `[X: {*}]` (renders `[X: {}]`); a leading number adds the cardinality as a
  `:measure`. A generic plural with a count renders as `@N`. *"three dogs see the
  man ."* → `[SEE]-(agnt)→[DOG: @3] (obj)→[MAN: #].` (A set with named members
  would be `[X: {...}@N]`.) See `test/extract-number-headless.lisp`. (Rendering
  the count required a fix to cgraph's formatter — `format-referent` was dropping
  a set's `:measure`.)
- **Quantifiers: extracted onto the concept.** A leading quantifier maps to
  `concept-quantifier`: all/every/each/any → `:universal`, some → `:existential`.
  Like tense/voice it's a stored slot, not shown in linear form. (PARSIFAL's
  loaded lexicon has all/some/any but not every/each.) See
  `test/extract-quantifier-headless.lisp`.
- **Definiteness: extracted onto the referent.** A definite NP ("the") gets the
  `#` referent (`[X: #]`); an indefinite NP ("a/an") stays bare (`[X]`).
  *"the man gives the woman a book ."* →
  `[GIVE]-(agnt)→[MAN: #] (obj)→[BOOK] (rcpt)→[WOMAN: #].` Read from the NP's
  `DEF`/`INDEF` feature. See `test/extract-determiner-headless.lisp`. (Quantifiers
  like "every", numbers/plurals, and named individuals are future work.)
- **Passive voice: extracted.** PARSIFAL normalizes a passive's roles (the
  logical object fills NEUT, agent only if a by-phrase is present), so roles need
  no new code; the passive participle is marked `concept-voice :passive`. (No
  copular *was*/agentive *by* in PARSIFAL's dictionary, so the available passive
  is the agentless participle, e.g. *"a meeting seems to have been scheduled ."*
  → embedded SCHEDULE is `:passive`. Voice isn't shown in linear form; it lives
  on the concept slot.) See `test/extract-passive-headless.lisp`.
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

Two layers:

**Unit suite** — runtime-free, safe in any loaded image:

```lisp
(asdf:test-system :cg-from-parse)   ; or
(cg-from-parse::test-all t)
```

**Headless integration tests** (`test/extract-*-headless.lisp`) — each brings up
the test-types catalog + a PARSIFAL grammar, parses a sentence, and checks the
extracted graph. They reset cgraph state, so run them in a *fresh* image, not
your working session. Run all of them with one command (prints a rollup, exits
non-zero on failure):

```sh
sbcl --non-interactive --disable-debugger \
  --eval '(ql:quickload :swank)' --eval '(ql:quickload :cg-from-parse)' \
  --load test/run-headless.lisp
```

(or `--load` any single `test/extract-*-headless.lisp`.)

To run them from a **live SLIME session** safely — without `exit` and restoring
your catalog + context afterward — load the runner once and call the interactive
entry point:

```lisp
(load (asdf:system-relative-pathname :cg-from-parse "test/headless-runner.lisp"))
(cg-from-parse::run-headless-interactive)
```
