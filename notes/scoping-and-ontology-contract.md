# Scoping the pipeline: grammar profiles + the ontology contract

The stack has **two** independent scope surfaces, one at each end of the pipeline,
and they are designed to compose:

```
   English text ──▶ PARSIFAL parser ──▶ parse tree ──▶ cg-from-parse extractor ──▶ conceptual graph
                    ▲                                   ▲
                    │ GRAMMAR PROFILE                   │ ONTOLOGY CONTRACT
                    │ (what INPUT is accepted)          │ (what the OUTPUT ontology must provide)
```

- A **grammar profile** bounds what *input* parses at all — a restricted profile
  makes `parse-sentence` **reject** (return `NIL` on) any construction whose rule
  groups it omits.
- The **ontology contract** bounds what *output* the extractor can emit — it
  declares the framework relations/types the extractor needs, and
  `validate-ontology` checks a mounted ontology provides them.

Together they bracket the pipeline: the grammar rejects out-of-scope sentences; the
contract rejects an ontology that can't represent what a sentence would produce.

---

## 1. Grammar profiles (parsifal — input scope)

Lives in `parsifal/system/grammar/clause-grammar.lisp`. The grammar is a list of
~35 named rule groups composed into `*full-grammar*` (Marcus's baseline +
`*grammar-extensions*`). A **profile** is a keyword → the list of rule groups to
register.

| symbol | role |
|---|---|
| `*grammar-profiles*` | registry: keyword → rule-group list. Ships `:full`, `:marcus`. |
| `register-grammar-profile name groups` | add/replace a profile (the one call to add one later) |
| `grammar-profile-groups name` | lookup; errors naming the known profiles |
| `load-grammar &optional (profile :full)` | reset the rule table and register a profile |

`load-full-grammar`/`load-marcus-grammar` are unchanged; `load-grammar` generalizes
them.

**The payoff is rejection.** A restricted profile that omits, say, the
that-complement rule group causes `"the man knows that the boy sees the dog"` to
**fail to parse** — even though every word is in the lexicon — while a simple clause
still parses. That is the point of a scoped/controlled-language front end: only
in-scope sentences get through.

**Rule groups are not freely detachable.** PARSIFAL is a deterministic wait-and-see
parser driven by rule priorities and packets; groups have dependencies (`VP-NP`
binding, `INITIAL-RULE` packet dispatch, the diagnostic rules). So a profile must be
a **coherent** subset, and each new profile needs its own regression test — an
*incoherent* subset does not reject cleanly, it ERRORs (drop `*quantifier-rules*` and
a live rule still refers to `QUANT-DONE`). See
`parsifal/test/integration/gram1-grammar-profile-test.lisp`.

**`:core` — the first scoped profile** (`*core-grammar*`). Simple declaratives only:
noun phrases (det + adjective), transitive **and** ditransitive clauses, pronouns,
proper names, locative/instrumental PP adjuncts, and manner adverbs. It **rejects**
clausal complements, relative clauses, wh-inversion, genitives, apposition, and
numbers/quantifiers. It is the input-scope companion of cg-from-parse's `:core`
ontology profile (next section) — the shared keyword is the contract.

---

## 2. The ontology contract (cg-from-parse — output scope)

Lives in `system/extract.lisp`. The extractor writes graphs over a **fixed set of
framework relations and abstract concept types** it names structurally, independent
of the input words (e.g. `agnt`/`obj`/`loc`/`prop`, `person`/`place`/`proposition`).
If a mounted ontology lacks one, extraction fails mid-sentence (under
`*on-missing-type* :error`) or degrades. The contract makes that a **loud, up-front**
check instead.

| symbol | role |
|---|---|
| `*ontology-requirements*` | the manifest: per-construction `(:relations … :concept-types … [:conventions …] :desc …)` |
| `*ontology-conventions*` | advisory structural conventions (e.g. gender `(sex)` marking) |
| `*ontology-profiles*` | profile → construction tags (`:full` → `:all`) |
| `validate-ontology &key (profile :full) stream` | check the loaded ontology; print a per-construction report; return `(values ok-p missing)` |

```lisp
(cg-from-parse:validate-ontology)          ; check your ~/.cgraph/types against :full
;; Ontology contract check (profile :FULL):
;;   ok       CLAUSE (base predicate-argument clause (agent + object))
;;   ...
;;   MISSING  EXCHANGE (...): relations has-part
;; => (values NIL ((:exchange :relation has-part)))
```

### Attributed per construction — this is what makes it compose

The manifest is keyed by **construction**, and `*ontology-profiles*` maps a profile
to the construction tags it needs. So a scoped grammar profile that can never parse
complements does not require the complement types, and
`validate-ontology :profile :core` checks only what `:core` can actually produce.
The grammar profile (§1) and the ontology profile are two halves of one
`(input-scope, output-scope)` deployment decision.

**`:core` ships**, wired to match the `:core` grammar:

```lisp
(:core . (:clause :ditransitive :pp-adjuncts :modifiers :proper-names))
```

a **proper subset** of `:full` — it omits `:complements`, `:exchange`, `:possessive`,
and `:anaphora`, so a `:core` deployment needs strictly less ontology (no
`proposition`/`situation`/`state`, no `has-part`, no `poss`, and not the gender
`(sex)` convention). Tags are per-construction, so a profile that supports a
construction even partially lists it (`:core` does PP adjuncts locatively but not
temporally, yet still lists `:pp-adjuncts`).

### Out of scope by design

The contract is the framework **skeleton**, not the lexicon. Deliberately excluded:

- **Domain lexemes** (`see`, `man`, `pay`, `hamburger`, …) — the mounted ontology's
  job for your text, with `*on-missing-type*` as the gap policy. (The exchange frame
  *creates* `pay`/`commercial-exchange` on demand under `:create`; they are content,
  not contract.)
- **The self-provided `prop` relation** — `ensure-complement-relation` creates it if
  absent, so it is never a requirement.
- **Relation dest types** (`place`, `manner`, `time-period`) — a relation's
  definition already entails its dest, so checking the relation covers them.
- **`exch`** — mapped in `*case-role->relation*` but the exchange-frame path
  restructures into `give`/`pay` + `has-part` and never emits it.

### The gender `(sex)` coupling, made explicit

Anaphora gender agreement reads a type's canonical `(sex)→[MALE]/[FEMALE]` arc
(`lemma-gender`). An ontology that marks gender differently silently disables the
check (resolution stays permissive — never wrong-by-force). This is declared as the
advisory `:gender-sex-arc` convention on the `:anaphora` construction, so it is
documented and **profile-gated**: a profile that can't reach the anaphora path
doesn't depend on it.

### Known gap

`validate-ontology` catches **over/mis-declaration** (a manifest label that no longer
resolves) — the self-check test proves the reference ontology satisfies `:full`, so
the manifest names only real vocabulary. It does **not** yet catch
**under-declaration** (a framework label the extractor emits but the manifest
forgot); that needs runtime capture of the labels an extraction actually touches, and
is future work. Test: `test/extract-ontology-headless.lisp`.

---

## Status

- Grammar-profile hook: **done** (parsifal). Profiles: `:full`, `:marcus`, `:core`.
- Ontology contract + `validate-ontology`: **done** (cg-from-parse), profile-aware.
  Profiles: `:full`, `:core`.
- `:core` demonstrates the pair end to end: the grammar rejects out-of-scope input
  and the ontology profile requires a strict subset of the framework vocabulary.
- Next: additional profiles as use cases appear (each = a coherent grammar subset +
  its ontology tags + a test); and closing the under-declaration gap in
  `validate-ontology` via runtime capture.
