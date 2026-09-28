# What happens when more than one sentence is in the room

Findings from `experiments/multi-sentence-kb.lisp`, run 2026-09-15 against the
mounted `cgraph-types` ontology. 26 sentences, one small domain, written inside
the register the parser supports and the vocabulary the ontology types, strict
(`:error`) throughout.

Every test in `test/` takes ONE sentence to ONE graph and stops. cgraph's
reasoning half — `project`, `maximal-join`, `query` over a context,
`say-query-results` — had never been pointed at extracted graphs. This is what
happened when it was.

## 1. Intake: 24 of 26

Two did not get in, and neither failure is the same kind of thing:

- **"the boy that Sue sees eats a hamburger ."** — no parse. A relative clause
  with a NAME as its embedded subject. Coverage; the sort of thing
  `notes/parser-front-ends.md` is about.
- **"Bob attends a party ."** — parsed fine, then the *ontology* refused it:
  `PARTY is not consistent with ENTITY, the out-arc type of the (obj) relation`.
  PARTY is under EVENT in the lattice, and `obj` wants an entity. **This is the
  type system working**, not a bug: you do not `obj` an event, you relate to it
  some other way. A graph database would have accepted the edge and quietly held
  a falsehood. Worth keeping as an argument for CG, not against it.

A third sentence, **"Sue has a dog ."**, failed on the first run with *no concept
type for lemma HAVE* — and that one was ours. `possession-clause-p` required a
common noun on BOTH sides, so every possessor with a NAME fell through to the
event path. `"the girl has a ball ."` worked; `"Sue has a dog ."` did not. Fixed
(the guard is really about the embedded CLAUSE, not the common noun), and
covered in `test/extract-possession-headless.lisp`. **One bug found simply by
writing two dozen sentences instead of one.**

## 2. Accumulation: 24 graphs go in, 1 comes out

`include-cgraph` combines a graph with any it shares concepts with. Over
extracted graphs it collapsed the entire corpus into a single graph in which:

```
[EAT]  has AGNT x8, OBJ x2
[SEE]  has AGNT x3, OBJ x4
[GIVE] has AGNT x4, OBJ x3, RCPT x4
```

One eating event with eight eaters. The knowledge base now asserts things nobody
said — that Sue ate the hamburger, that the child saw Bob.

**The join is not wrong.** Every extracted event concept is GENERIC — `[EAT]`
with no referent — and joining two generic concepts of the same type is exactly
what Sowa's formation rules license. The graphs never said these were different
eatings, so the machinery was entitled to assume they were one.

Also worth knowing: **combining is destructive**. It rewires the input graphs in
place, so a "flat" store and a "joined" store built from one extraction are the
same objects. (The first run of the experiment measured the flat store *after*
joining and reported Sue mentioned in 900 sentences.)

## 3. Identity: Sue is 13 different people

13 mentions of "Sue", 13 distinct individual ids, `same-individual-p` → NIL.
`named-concept` calls `make-individual`, which mints a fresh id every time, so
each sentence gets its own Sue.

This is the same silence as §2, read from the other end. **Events over-merge
because they are generic; individuals under-merge because they are always
fresh.** Nothing in an extracted graph says *which* thing it is about.

## 4. Retrieval: this part works

Against the unjoined store, with `*package*` bound to `:cg` (the reader interns a
bracketed `[TYPE]` in the current package, so a pattern read from any other
package has no known types in it):

| query | answer |
|---|---|
| `[EAT]-(agnt)->[PERSON: *x].` | Bob, the girl, the woman, the man, Sue |
| `[DRIVE]-(agnt)->[PERSON: *x].` | Sue |
| `[PERSON: *x]<-(agnt)<-[GIVE].` | Bob, Sue, the woman |
| `[DOG]<-(poss)<-[PERSON: *x].` | Sue |

Real question answering over a knowledge base built from English, with the
answers available back in English through `say-query-results`. Against the
*joined* store the same questions still return the right distinct bindings, but
the result counts explode (36 results for one binding) as projection finds every
path through the merged blob.

## 5. Join, by hand

```
"Sue eats a pie ." + "Sue is eating a pie ."   ->  [EAT]-(agnt)->[PERSON: Sue]
                                                       (agnt)->[PERSON: Sue]
                                                       (obj) ->[PIE]
"Sue eats a pie ." + "Bob eats a hamburger ."  ->  [EAT]-(agnt)->[PERSON: Bob]
                                                       (agnt)->[PERSON: Sue]
                                                       (obj) ->[HAMBURGER]
                                                       (obj) ->[PIE]
```

Two sentences that describe the *same* event and two that describe *different*
events produce the same shape, and the first does not even unify its two Sues.
`maximal-join` has nothing to tell them apart with.

## 6. The fix, tested: individuate

Hypothesis: §2 and §3 are one failure. So, as a post-pass over the graphs (NOT
in the extractor — the question was what CG does once individuation exists):

- every event concept with no referent gets a fresh individual — *this* eating,
  not eating in general;
- every named concept gets the one canonical individual for its (type, name) —
  Sue is one person corpus-wide.

Same corpus, same machinery, measured again:

| | before | after |
|---|---|---|
| "Sue" distinct ids | 13 | **1** |
| `same-individual-p` | NIL | **T** |
| graphs after `include-cgraph` | 1 | **2** |
| events merged that shouldn't be | 6 kinds | **0** |

The residue is two `[COMMERCIAL-EXCHANGE: #...] has PART x2`, which is not a
merge at all — the exchange frame has two halves by construction.

And the two remaining graphs are the right two: everything connected to Sue
became ONE graph — one Sue node with her eating, driving, giving, paying and dog
hanging off it — and everything else the second. **That is a knowledge base**,
and it is what `include-cgraph` was always trying to build.

> **UPDATE 2026-09-28 — sections 2, 3 and 6 are now history.** The fix predicted
> in §6 was built, in the emitter rather than as a post-pass
> (`system/identity.lisp`), and it reaches these numbers on the way in: "Sue" 1
> id, `same-individual-p` T, 24 graphs -> 2, zero events wrongly merged. §3's 13
> Sues and §2's `[EAT]` with eight agents describe the system as it was. The
> two named next steps below are done; the third — what `include-cgraph` is for
> — is still open. See `notes/next-steps.md`.

## What this says about the original question

The reasoning machinery is sound and does what the theory says. What it needs
from the extractor is **referents that identify**, and that is a small, specific
change rather than a rethink:

1. **Event individuation.** Give each predicate concept an individual referent.
   Costs: every expected test string gains a referent (`[EAT: #12]`), and
   `say` must keep rendering it as "eats", not "the eating #12".
2. **A name registry.** One individual per (type, name) per knowledge base, not
   per extraction. Needs a session-scoped registry, which is also exactly what
   CROSS-SENTENCE anaphora would need — "Sue ... she ..." across two sentences is
   the same problem wearing a different hat (§12 in `next-steps.md` is
   intra-sentence by construction).
3. **Then decide what `include-cgraph` is for.** Joining on ingest is a policy,
   not a law. A store that keeps sentences separate and joins on demand answers
   queries just as well and cannot invent anything.

None of that is a parser question, which is the point: this is the half of the
project where the interesting problems are.
