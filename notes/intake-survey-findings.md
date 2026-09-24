# Which layer refuses a sentence

Findings from `experiments/intake-survey.lisp`, run 2026-09-23 against the
mounted `cgraph-types` ontology. 87 sentences in two bands, strict (`:error`)
throughout.

`notes/parser-front-ends.md` argued that the bill for the recent one-off fixes
was mostly *coverage* rather than *determinism*, and `driver.lisp` already warned
that "parsing on without the vocabulary you asked for is how a lexicon gap gets
mistaken for a grammar gap." Neither claim had ever been measured. This measures
it, by classifying every refusal into the layer that produced it:

| layer | what it costs to fix |
|---|---|
| **lexicon** | parser has no entry for some word — a dict line |
| **grammar** | every word known, still won't parse — **real parser work** |
| **ontology / no type** | parsed, but a lemma has no concept type — a type definition |
| **ontology / contract** | parsed and typed, and the **lattice refused an arc** — nothing; this is the type system working |
| **extractor** | everything upstream fine and we broke — our bug |

Only the *grammar* row is an argument about parsers. That is the number the
three-way direction question (extend PARSIFAL / replace it / build a CG-driven
parser) actually turns on.

## The domain is 61 words wide

The binding constraint is neither the parser nor the ontology but their
**intersection**. PARSIFAL's dictionary (`defs-dictionary.dict` +
`supplement.dict` + the domain's `lexicon.dict`) defines 493 words. The mounted
ontology defines 247 concept types. **61 content words are in both:**

```
act ask attend automobile ball baltimore book bottle box boy bread breakfast buy
cheese cherry child dinner dog dollar drive eat friday fruit girl give gladly
hamburger hope house kitchen know letter lunch man manner monday party pay person
pick-up pie place quickly red rock saturday see sell sit soup sunday tell thought
thursday today tomorrow tuesday water wednesday woman yesterday
```

432 further dictionary words (`car`, `cat`, `friend`, `meet`, `hit`, `like`,
`believe`, `arrive`, `want`, `be`, …) parse but have no concept type. That gap —
not the grammar — is what a user hits first.

One entry in that list is a mirage: **`thought` is in the ontology and in the
dictionary, but morpho reads it as the past tense of `think`**, so "a thought"
does not parse as an NP. Name-matching the two vocabularies overstates the
intersection slightly; `validate-lexicon` pairs them by name and would not catch
this either.

## Band A — in-register: 61 of 62 (98.4%)

Built only from the 61-word intersection, spread across every construction the
extractor claims to handle: transitive, ditransitive (both orders), genitive,
possessive pronoun, possession, exchange, clausal complement, PP adjunct (loc and
time), bare temporal, licensed PP, adjective, noun-noun compound, progressive,
future, passive, adverb, subject relative, wh- and yes/no question, imperative,
apposition, number, quantifier.

| layer | n | % |
|---|---|---|
| extracted | 61 | 98.4 |
| ontology / **contract refusal (correct)** | 1 | 1.6 |

**Zero lexicon gaps, zero grammar gaps, zero missing types, zero extractor bugs.**

The single non-entry is `"Bob attends a party ."`, the same correct refusal the
KB experiment found: PARTY is under EVENT and `obj` wants an ENTITY. It is on the
credit side of the ledger.

## Band B — stretch: 6 of 25 (24%)

Sentences a user would plausibly write next, each carrying a *predicted* layer so
a wrong prediction is itself a finding.

| layer | n | % |
|---|---|---|
| ontology / no type | 10 | 40.0 |
| **grammar** | 5 | 20.0 |
| lexicon | 4 | 16.0 |
| extracted | 6 | 24.0 |

**Ontology and lexicon gaps outnumber grammar gaps 14 to 5.**

The five real grammar gaps are worth naming, because they are the entire case for
touching the parser:

- **coordination**, both clausal ("Sue eats a pie and Bob eats a hamburger") and
  NP ("the boy and the girl eat a pie");
- **object relatives** ("Bob sees the boy that Sue knows", "the boy that Sue sees
  eats a hamburger") — already recorded as open in `next-steps.md` §4;
- **predicate adjectives** ("the pie that Sue eats is red").

Note that `that`-relatives are not merely unimplemented: the lexicon gives `that`
only `DET\COMP-AMBIG`, with no relative-pronoun feature at all. The supported
form is `who` with a subject gap, and it works
("the boy who sees the dog sees the woman" is band A and extracts).

## The predictions that were wrong were wrong in the good direction

19 of 25 correct. Every miss but one was the parser doing **better** than
expected:

| sentence | predicted | actual |
|---|---|---|
| "Sue does not eat a pie ." | grammar | **extracted** |
| "Sue eats a pie in the kitchen on Monday ." | grammar | **extracted** |
| "Sue eats the pie quickly in the kitchen ." | grammar | **extracted** |
| "Sue ate a pie yesterday ." | grammar | **extracted** |
| "Sue wants to eat a pie ." | grammar | ontology / no type |
| "there is a dog in the kitchen ." | grammar | ontology / no type |

Negation, stacked adjuncts, adverb-plus-PP and past tense all work. And the last
two are the sharpest result in the file: **subject control and the existential
both parse**, and are stopped only by `WANT` and `BE` having no concept type.
Those are one-line ontology additions standing in front of two constructions the
grammar already handles.

## What this says about the direction question

Across both bands, 87 sentences: **5 grammar gaps (5.7%)** against **14
lexicon-or-ontology gaps (16.1%)**. Inside the register the system claims, the
grammar did not fail once.

So the case for replacing PARSIFAL is not supported by our own corpus. What
limits the system today is the 61-word intersection, and the cheapest way to
widen it is type definitions and dictionary entries, not a different parser.
That agrees with `parser-front-ends.md`'s conclusion and now has numbers under
it.

The caveat that note already stated still holds and is not touched by this
measurement: these sentences are *ours*. On arbitrary text the ranking would
invert, and determinism's real price — a hand-written lookahead rule per
lexically ambiguous word, and no notion of preference — would dominate. This
measures the register we work in, which is the register the project is for.

## Identity, again

Carried over as a secondary number: **"Sue" appears 29 times across the corpus
and carries 28 distinct individual ids.** (The one shared pair is an
intra-sentence coreference.) The KB experiment's finding scales exactly as
predicted — see `kb-experiment-findings.md` §3, and note that the mechanism is
now understood: cgraph's context *has* an identity cache (`cache-concept` /
`retrieve-concept`, keyed by type + individual / id / properties), and the
extractor never calls it. `extract.lisp:1794` binds a fresh child context per
extraction and `:1795` carries identity in `*node->concept*`, a hash table
rebound per extraction and keyed by parse node — intra-sentence by construction.

Lookup would have to go by **properties** (`retrieve-concept ctype '(:name
"Sue")`), not by individual: `individuals-equal` now compares the id (see
cgraph's `known-issues.md`), so two Sues with different ids are correctly not
equal.

**This, not the parser, is where the next real work is.**
