# Parser front ends — is PARSIFAL the right parser for this?

**Status: OPEN, but now MEASURED. Raised and deferred 2026-09-15 (time).**
Decision record, not a plan of record. Nothing in the code depends on this file.

> **2026-09-23: the coverage-vs-determinism split below has numbers under it.**
> `experiments/intake-survey.lisp` classified 87 sentences by which layer refused
> them. In-register: 61/62, with zero grammar gaps. Across both bands: 5 grammar
> gaps against 14 lexicon-or-ontology gaps. The domain is bounded by the 61-word
> intersection of PARSIFAL's dictionary with the ontology, not by the grammar.
> See `notes/intake-survey-findings.md`. The argument below is unchanged; it is
> the corpus that has stopped being hypothetical.

The question, asked after a run of one-off parser fixes (`her`, noun compounds,
bare temporals, apposition): *are we fixing these because of PARSIFAL's design,
or would any parser need this? Is PARSIFAL the wrong parser here? What else is
there?*

## What we are actually paying for

Of the eleven entries in parsifal's `EXTENSIONS.md`, about three are *ambiguity*
work forced on us by determinism:

- #5 `det\relpron-ambig` for `what` (Marcus's own WHAT-DIAG)
- #8 the existential vs. reduced-relative fork
- #11 `her` as determiner (2026-09-14)

The other eight are *coverage* — apposition, manner adverbs, bare temporal
adjuncts, noun-noun compounds, `buy`/`sell`, the give-class TIME case, `name` in
`*as-types*`, the lexicon inventory. Those are not design consequences at all.
Marcus never wrote a compound-noun rule because compounds were not what he was
demonstrating. Any hand-built grammar of that size would have the same holes,
deterministic or not.

So the bulk of the bill is **a 1978 demonstration grammar and a few-hundred-word
lexicon**, not the determinism hypothesis. PARSIFAL is an existence proof that
passives, relatives, wh-movement, control and raising can be parsed with a
three-cell buffer and no backtracking. It is a thesis artifact; gram1–gram5 was
never meant to be wide-coverage.

### Where the design does cost us, permanently

Determinism has a real recurring price, and `her` is its shape: **every lexically
ambiguous word needs a hand-written lookahead rule**, because the parser cannot
revise. That bill keeps arriving — `that` (determiner / complementizer /
relative), noun-verb pairs ("the plant"), `-ing` forms, bare plurals. A chart or
statistical parser pays nothing for these; ambiguity simply survives until
context kills it.

The deeper limit is that PARSIFAL **has no notion of preference**. "I saw the man
with the telescope" has no syntactic answer, only a likelier one. A deterministic
parser must commit, and the only way to steer it is another rule. In the
well-behaved register we test in, this rarely bites. On real text it would
dominate.

### What PARSIFAL gives us that most alternatives do not

Marcus's **case frames** are why `extract.lisp` is as small as it is. `(cf (neut)
(pto) agt)` on `drive` hands us thematic roles that map nearly directly onto CG
relations (`*case-role->relation*`). A dependency parser gives grammatical
functions (`nsubj`/`obj`/`obl`), not verb-specific semantic cases; recovering
roles then needs a separate SRL pass or a role lexicon. Any replacement has to
pay this back.

## The seam we already have

`system/extract.lisp` is the only file that knows what a `pa::` node is. It ends
at an IR — a plain plist — and `ir->cgraph` takes it from there:

```
parse->ir   : PARSIFAL parse -> IR      <- the only PARSIFAL-shaped code
ir->cgraph  : IR -> cgraph graph        <- ontology, relations, emission
say-graph   : cgraph graph -> English   <- round-trip gate
```

IR shape (see the commentary at the top of `extract.lisp`):

```lisp
(:kind :clause :pred P :spec S :tense T :aspect A :voice V
 :clause-type CT :node N
 :cases ((:role R :gfunc G :filler FILLER-IR) ...)
 :adjuncts (...) :adverbs (...))
```

with filler IRs `(:kind :entity|:named|:trace|:query|:backref|:empty ...)`
carrying `:lemma :determiner :quantifier :number :count :adjs :nmods :poss
:appos :mods`.

**A second front end means a second producer of that plist.** `ir->cgraph`, the
ontology contract, `validate-ontology`, the capture test, `say`, the round-trip
gate and all 32 headless tests keep working untouched, and both front ends can be
run on the same sentence and their graphs diffed. That is the cheap experiment;
a rewrite is not on the table.

## ERG — the candidate

**ERG = English Resource Grammar**: a hand-built HPSG grammar of English, Dan
Flickinger (Stanford/CSLI) from the early 1990s, maintained by the DELPH-IN
consortium. Think of gram1–gram5 after thirty more years of people finding
sentences it got wrong. Tens of thousands of lexical entries; `her` as both
determiner and pronoun was settled in it long ago.

It is a grammar file, not a program. Processors that run it:

| processor | language | note |
|---|---|---|
| **ACE** | C | fast, the usual choice; `ace -g erg.dat` |
| **PET** | C++ | older |
| **LKB / LKB-FOS** | **Common Lisp** | the development environment; FOS runs on SBCL — see "In Lisp?" below |

Ambiguity is handled the opposite way from PARSIFAL: build a packed forest of all
analyses, then rank them with a model trained on the Redwoods treebank and take
the top one (or top *n*). No rule-writing per ambiguous word.

### What it returns

**MRS** (Minimal Recursion Semantics) — a flat bag of elementary predications
with variables, handles and scope constraints. "The woman sees her dog" is
roughly:

```
_the_q(x3), _woman_n_1(x3), _see_v_1(e2, x3, x9), _dog_n_1(x9),
poss(e14, x9, x11), pronoun_q(x11), pron(x11)     ; x11: PERS 3, NUM sg, GEND f
```

plus tense/aspect/mood on the event variable `e2`. Two graph-shaped projections,
**DMRS** and **EDS**, are what we would actually consume: directed labelled
graphs, already close to a conceptual graph. `poss(e, x9, x11)` is our `(poss)`
arc, pointing the right way.

### The catch

**ERG's `ARG1`/`ARG2` are not thematic roles.** It deliberately declines to say
whether `ARG1` is an agent or an experiencer. So we lose exactly what Marcus
gives free and must rebuild it as a predicate → role table (`_see_v_1` ARG1 →
`expr`, ARG2 → `obj`, ...). That table is the bulk of the work, and it is the
same shape as `*case-role->relation*` plus the ontology contract we already keep.

It also would not make everything easy: the ERG has its own conventions to
translate (quantifier scope, `udef_q`, message predicates), and its output is
large. What it does buy is that **coverage stops being our problem**.

## Alternatives surveyed

| option | output | fit here |
|---|---|---|
| **ERG + ACE** | MRS / DMRS / EDS | best semantic fit; graph-shaped; roles must be added |
| **CCG + Boxer** (C&C, EasyCCG, depccg) | DRT / DRS | compositional, graph-ish, good role info |
| **Stanza / spaCy / UDPipe** | UD dependencies | cheapest to adopt, shallowest; needs SRL for roles |
| **AMR parsers** | AMR graph, PropBank roles | already a semantic graph; skips syntax; idiosyncratic conventions |
| **GF** | abstract syntax, bidirectional | parses *and* generates from one grammar — interesting because we care about round-trip; controlled-language coverage |

## In Lisp?

Essentially nothing wide-coverage — with one exception worth checking.

- **LKB / LKB-FOS** is written in Common Lisp and runs the ERG. LKB-FOS targets
  SBCL. If that still holds, an ERG front end could be **in-image Lisp** rather
  than a subprocess, which changes the dependency story completely. *Verify
  before relying on it.*
- **cl-conllu** (Rademaker et al.) reads/writes CoNLL-U — i.e. let something else
  parse and consume the result in Lisp. The pragmatic bridge for the UD options.
- **cl-nlp** — tokenizers, tagger, odds and ends; not a wide-coverage parser, and
  quiet for years.
- Everything else (Stanford, Berkeley, spaCy, Stanza, ACE) is an **external
  application**: a subprocess plus a text/JSON protocol, not a library we link.

## If and when we pick this up

1. **Seam first, no download.** Capture MRS/EDS text for a handful of sentences
   we already test, check the fixtures into `test/erg-fixtures/`, and write
   `system/erg.lisp`: an EDS reader, `*erg-role-map*`, and `eds->ir` producing
   the *same* plist `parse->ir` builds. A headless test runs a fixture straight
   through `ir->cgraph` and `say`. This proves the IR is really the contract and
   needs no binary on the machine.
2. **Then the processor.** ACE binary + ERG grammar image (~100MB) — a network
   fetch of a third-party binary; historically x86-64 on macOS, so expect a
   Rosetta or build-from-source detour on Apple Silicon. Or LKB-FOS in-image, if
   the SBCL story holds.
3. **Then compare.** Run both front ends over the headless corpus and diff the
   graphs. That is the honest measure of what a real parser buys us on our own
   sentences, and it is cheap to abandon if the answer is "not much".

Nothing here is urgent, and none of it is a reason to stop extending PARSIFAL: if
the goal is partly to understand deterministic parsing and CG, the extension work
*is* the project. The question only becomes pressing if the goal shifts to
reading arbitrary English.
