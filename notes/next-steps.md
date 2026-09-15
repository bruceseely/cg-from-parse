# cg-from-parse — next steps

> GENITIVES — DONE (2026-07-01), the first PARSIFAL-side (grammar) feature.
> Common-noun, proper-name, AND possessive-pronoun genitives all parse and
> extract:
>   "the man 's dog sees the woman ." -> [SEE]-(agnt)->[DOG:#]<-(poss)<-[MAN:#]
>                                                   (obj)->[WOMAN:#].
>   "mitch 's dog sees the woman ."   -> [DOG:#]<-(poss)<-[PERSON:Mitch]
>   "my dog sees the woman ."         -> [DOG:#]<-(poss)<-[PERSON:I]  (:create; I not in test-types)
> PARSER side (parsifal system/grammar/clause-grammar.lisp *genitive-rules*,
> both rules verbatim from Marcus gram3.l, added to *full-grammar*):
>   - POSS-NP (IN NP-COMPLETE, [=poss]): attach the clitic `'s to a just-completed
>     NP, re-label it poss-np, then `Run np-done next'. The "Run np-done next" is
>     REQUIRED (Marcus's bare rule stalled here): without it the parser resumes
>     normal selection and STARTNP (priority 10) grabs the head noun before the
>     poss-np drops to CPOOL. Forcing np-done drops the poss-np so POSSESSIVE-DET
>     (priority 5) fires first. (Mirrors END-OF-NAME, which already did this for
>     names.)
>   - POSSESSIVE-DET (AS, priority 5, IN CPOOL, [=poss-np]): wrap the poss-np in a
>     fresh POSS-DET det node (ngstart, def); STARTNP/DETERMINER then make it the
>     head noun's determiner. So the head NP is definite and det->np is the
>     possessor. Names (END-OF-NAME) and poss-pronouns (PRONOUN rule) already
>     produced poss-nps, so they got genitives for free.
> EXTRACTOR side (system/extract.lisp): np-possessor reads the head NP's poss-det
> -> possessor NP; np-possessor-ir recurses filler->ir (so the possessor is a full
> entity/named/pronoun); the entity IR gains :poss; emit-possessor emits
> [POSSESSOR]->(poss)->[NOUN] with the possessor as the ANIMATE *source* (reverse
> of emit-modifier, since `poss' is ANIMATE->ENTITY) -- arc-source-ok-p guards a
> non-animate possessor. *possessive-relation* = poss. Tests:
> parsifal/test/integration/gram1-genitive-test.lisp (parse structure, 13 asserts)
> and test/extract-genitive-headless.lisp (extraction, strict :error). No
> regressions: parsifal full-grammar + coverage(47) + NP tests green; 19/19
> cg-from-parse headless.
>
> APPOSITION -- DONE (2026-07-07), the FIRST non-Marcus grammar rule (gram1-5
> and the 1977 appendix have no apposition), so it lives in *grammar-extensions*
> (not *marcus-full-grammar*) -- see the grammar-promotion note below.
>   "the dog , spot sees the woman ." -> [SEE]-(agnt)->[DOG: Spot] (obj)->[WOMAN:#]
> The head NP keeps its SPECIFIC type (dog) and the appositive supplies the NAME,
> so the named individual is [DOG: Spot], not the name marker's broad [ANIMAL:
> Spot]. Works in subject AND object position.
> PARSER side (parsifal *apposition-rules*, one rule): APPOSITIVE IN NP-COMPLETE
> on [=apunc][=name] -- the comma (apunc) sits in 1st so PROPNAME (an attention
> shift needing a name in 1st) never fires; consume the comma (1st) AND the name
> NP (2nd -- PROPNAME builds it during lookahead, and its `* is not np' guard
> stops it re-triggering) in one rule, as gram1 NP-UTTERANCE grabs 1st+2nd,
> attaching the name under the head's `appos' daughter, then Run np-done next.
> Default priority 10 beats NP-DONE (15) so it intercepts before the NP finalises.
> EXTRACTOR side (system/extract.lisp): np-appos-name reads the head NP's `appos'
> daughter (a name NP) -> the name string; filler->ir adds :appos to the entity
> IR; emit-filler's :entity branch, when :appos is set, replaces the concept's
> referent with a NAMED individual of the head's OWN type ([DOG: Spot]). Tests:
> parsifal/test/integration/gram1-apposition-test.lisp (13 asserts, incl. object
> position + a no-comma negative) and test/extract-apposition-headless.lisp
> (strict :error). No regressions: parsifal 56/56 integration; cg 20/20 headless.
>
> ALSO (2026-07-07, before apposition): promoted the grammar out of the test tree
> to parsifal/system/grammar/clause-grammar.lisp (was test/integration/), and
> split *full-grammar* into *marcus-full-grammar* (verbatim ports) +
> *grammar-extensions* (ours) with a `load-marcus-grammar' baseline entry point.
>
> PP ADJUNCTS (locative) -- DONE (2026-07-07, extractor-only; see #5 below).
> Turned out NOT parser-blocked: PARSIFAL attaches an unlicensed PP to the S node
> as a surface `pp' daughter (gram5 PP-UNDER-S-1), so no grammar change was needed
> -- the extractor just walks clause pp daughters and maps the preposition to a
> relation (locatives -> loc). "the man sees the dog in the city ." ->
> [SEE]-(agnt)->[MAN:#] (obj)->[DOG:#] (loc)->[CITY:#]. NOT in *grammar-extensions*
> (no parser change) and NOT in parsifal EXTENSIONS.md.
>
> NON-LOCATIVE + TEMPORAL PREPOSITIONS -- DONE (2026-07-07): `with' -> inst
> ("... with the telescope ." -> (inst)->[TELESCOPE:#]); temporal PPs -> `time'
> either via a dedicated temporal prep (before/after/...) or a time-NP object
> ("on monday" -> (time)->[MONDAY:#]), which resolves the loc/time ambiguity of
> in/on/at by the object's type. adjunct-relation(prep,obj) in extract.lisp; added
> telescope + monday to cgraph test-types. Extractor-only, not in EXTENSIONS.md.
>
> MANNER ADVERBS -- DONE (2026-07-07): SECOND grammar extension. "the man sees the
> dog quickly ." -> [SEE]...(manr)->[QUICKLY]. Lexicon (quickly/slowly in
> supplement.dict) + ADVERBS-ADJUNCT rule (*adverb-rules* IN SS-FINAL, our
> *grammar-extensions*) + extractor (clause-adverb-lemmas -> emit-modifier w/ manr).
> See parsifal EXTENSIONS.md #2. cg 22/22, parsifal 56/56.
>
> DEICTIC adverbs -- DONE (2026-07-15), extractor-only, rounding out #5.
>   "the man sees the dog here ."  -> [SEE]...(loc)->[HERE]
>   "the man sees the dog there ." -> [SEE]...(loc)->[THERE]
>   "the man sees the dog today ." -> [SEE]...(time)->[TODAY]   (already worked)
>   "the man sees the dog now ."   -> [SEE]...(time)->[NOW]     (already worked)
> Marcus's dictionary already lexicalizes these as pseudopropnoun place/time NOUNS
> (defs-dictionary.dict), so NO grammar change -- purely extractor. Two landing
> spots (found by probing, not assumed): TIME deictics (today/now) are wrapped by
> PARSIFAL in a synthetic `during' PP, so the existing PP-adjunct path
> (clause-adjuncts) ALREADY emitted them as (time) -- no work needed. PLACE deictics
> (here/there) land as a stray `np' daughter of the VP -- not a case, not a PP -- so
> nothing walked them. NEW extractor bits (system/extract.lisp): *deictic-relation-
> features* (pa::place->loc, pa::time->time), deictic-relation (relation for a
> pseudopropnoun np by its head feature), and clause-deictic-adjuncts (walk the VP's
> non-case `np' daughters, turn each place/time deictic into a bare adjunct IR with
> :prep NIL -- emit-adjunct then links it off the predicate exactly like a PP
> adjunct). Wired into clause->ir's :adjuncts (append after clause-adjuncts).
> here/there added to cgraph test-types (both ⊑ place) so here/there run strict
> (:error); today/now use :create (deictic, not test-types), like the manner-adverb
> test's `quickly'. Test test/extract-deictic-headless.lisp. Whole stack green
> (run-all-suites.sh): cg 24/24, parsifal + parsifal-integration + cgraph all PASS.
> Extractor-only, so NOT in parsifal EXTENSIONS.md (no parser change).
>
> POSSESSIVE ANAPHORA -- DONE (2026-09-14), extractor-only, extending #12.
>   "John will drive his automobile to Baltimore ." ->
>     [DRIVE:@future]-(agnt)->[PERSON:John *x] (dest)->[BALTIMORE]
>                     (obj)->[AUTOMOBILE:#]<-(poss)<-[PERSON:John *x]
> Before this, a possessive pronoun never resolved: the (poss) arc came from a
> stray indexical [PERSON: He] that had nothing to do with the agent. The
> resolver's first configuration (#12) only fires for a pronoun that is a CASE
> FILLER of an embedded complement, and a genitive possessor is a filler of no
> clause at all, so it always fell through to the indexical.
> SECOND CONFIGURATION (system/extract.lisp, possessive-antecedent): a 3rd-person
> possessive pronoun corefers with the SUBJECT of the clause it sits in. This one
> is SAME-clause, which #12's rule deliberately avoids -- and is safe for a reason
> that does not hold there: a possessor sits inside an NP, so it is never a
> co-argument of the subject and Principle B never applies ("John drives his car"
> binds where "John sees him" may not). The guard is circularity instead: the
> possessive must not sit inside the subject NP itself, or the antecedent would
> contain the anaphor -- "his dog sees the man ." keeps [PERSON: He]
> (node-dominated-p compares PARSIFAL `collectw' leaf sets, so no parent pointers
> are needed). A subject that is itself a resolvable pronoun hands on ITS
> antecedent, so "the man knows that he sees his dog ." puts [MAN:?x1] on the
> (poss) arc rather than an intermediate pronoun node no concept is registered
> under. Same agreement gate as #12 (number/person/gender), same *resolve-anaphora*
> switch, same emission path: a resolved possessive becomes a :trace IR and the
> EXISTING emit-trace machinery realizes it -- same context shares one concept node
> (the [PERSON: John *x] above IS the agent's concept), a crossed context mints
> *x/?x. Plumbing: filler->ir takes :possessor-of, np-possessor-ir passes the host
> NP, anaphor-antecedent dispatches on it. Round-trips: say-graph gives back "The
> man sees his dog." Tests in test/extract-anaphora-headless.lisp (resolve,
> possessive-in-subject negative, embedded chain). 32/32 headless green.
>
> POSSESSIVE `HER' -- DONE (2026-09-14), parser + generator, one sentence's worth
> of bug in two layers.
>   "the woman sees her dog ." -> [SEE]-(agnt)->[WOMAN:#*x]
>                                      (obj)->[DOG:#]<-(poss)<-[WOMAN:#*x]
>                                 say: "The woman sees her dog."
>   "the woman sees her ."     -> [SEE]-(agnt)->[WOMAN:#] (obj)->[PERSON:She]
>                                 say: "The woman sees her."
> PARSER (parsifal, EXTENSIONS.md #11): `her' is BOTH the accusative pronoun and
> the possessive determiner, and Marcus's dictionary enters only the first --
> giving the possessive to `hers', which in English is the INDEPENDENT possessive
> ("the dog is hers") and never a determiner. So "her dog" parsed as the object
> `her' plus a stranded `dog', and the head noun was dropped without a word:
> [SEE]-(agnt)->[WOMAN:#] (obj)->[PERSON: She], no DOG anywhere. Marking `her'
> poss-pronoun instead would fix that sentence by breaking "sees her" (PRONOUN
> labels a poss-pronoun NP a poss-np, and POSSESSIVE-DET then waits for a head
> noun that never comes), so the ambiguity is resolved from CONTEXT, in the shape
> of Marcus's own WHAT-DIAG: supplement.dict marks `her' `poss-ambig', and
> POSS-PRONOUN-DIAG (*possessive-pronoun-rules*, priority 4 in npool) adds
> `poss-pronoun' when the next cell starts a noun group. It marks `poss-diag' on
> both branches, or the no-op branch would match itself forever. No extractor
> change: once the parse is right, the genitive path and the possessive-anaphora
> rule above already handle it (and "the man sees her dog ." keeps [PERSON: She]
> on the gender clash, which is the agreement gate doing its job).
> GENERATOR (cgraph): an INDEXICAL pronoun -- an individual whose NAME is a
> pronoun, which is what an unresolved `her'/`he'/`you' leaves in the graph --
> was realized as an ordinary proper name: "The woman sees She.", "She's dog",
> "You sees the dog." A pronoun inflects for CASE, which a name never does, and
> carries a PERSON, which a name always settles as third.
> *personal-pronoun-forms* (generation/lexicon.lisp) gives the case forms plus
> person and number; realize-np answers from it before any article/modifier logic
> (a pronoun IS a noun phrase, and is what a revisit would produce anyway), the
> possessive-prefix path uses it for "her dog" over "She's dog", and
> concept-person/concept-number read it so the verb agrees -- which fixes
> "I see the dog." / "You see the dog." as the same bug's other face.
> Tests: parsifal test/integration/gram1-possessive-pronoun-test.lisp (both
> readings, subject genitive, unambiguous pronouns untouched); cgraph
> generation-test (8 indexical-pronoun cases) -- AND generation-test added to
> test-all, where it had never been listed though green and built, so the one
> suite checking what the generator SAYS was ungated; cg-from-parse
> extract-anaphora-headless (both readings end to end). Whole stack green.
>
> NEXT UP: anaphora (#12, still deferred) or a new area.
>
> MULTI-SENTENCE KB EXPERIMENT -- DONE 2026-09-15 (experiments/multi-sentence-kb.lisp,
> findings in notes/kb-experiment-findings.md). First time cgraph's REASONING half
> (project/maximal-join/query/say-query-results) was pointed at extracted graphs:
> 26 sentences, one domain, strict typing. Query works -- real question answering
> over a KB built from English, answers said back in English. Accumulation does
> not: include-cgraph collapsed 24 graphs into 1 ([EAT] with AGNT x8), because
> every extracted event is GENERIC and joining two generic same-type concepts is
> exactly what the formation rules license; and "Sue" was 13 distinct individuals,
> because named-concept mints a fresh individual per extraction. One failure, two
> directions: nothing in an extracted graph says WHICH thing it is about. Tested
> the fix as a post-pass (individuate events + one individual per (type,name)):
> Sue -> 1 id, same-individual-p T, 24 graphs -> 2, zero events wrongly merged,
> and the 2 are the right 2 (one Sue-hub, one for the rest). NEXT, if this is the
> direction: event referents + a session-scoped name registry in the emitter --
> the latter is also what CROSS-SENTENCE anaphora needs, so #12's open half and
> this are the same problem. Also FOUND + FIXED a real bug the experiment
> surfaced: possession-clause-p demanded a common noun on BOTH sides, so "Sue has
> a dog ." died looking for a HAVE concept type while "the girl has a ball ."
> worked (the guard is about the embedded CLAUSE, not the common noun).
>
> OPEN ARCHITECTURE QUESTION (raised 2026-09-15, deferred -- no work started):
> is PARSIFAL the right front end? Written up in notes/parser-front-ends.md --
> the coverage-vs-determinism split behind the recent one-off fixes (of the 11
> parsifal EXTENSIONS.md entries, ~3 are determinism's bill and 8 are a 1978
> demonstration grammar's coverage), why the IR (`parse->ir' -> `ir->cgraph') is
> the seam a second front end would target, what ERG/MRS would give and cost (its
> ARGn are NOT thematic roles -- Marcus's case frames are what make extract.lisp
> small), the alternatives, and whether any of it can be Lisp (LKB is, and runs
> the ERG -- worth verifying). Nothing in the code depends on that note.

Punch list for continuing the PARSIFAL → conceptual-graph extractor. Roughly in
priority order. Current state (2026-06-25): transitive clauses, control
coreference (shared-node + cross-context `?x`), and clausal-complement embedding
as `[PROPOSITION: …]` all work end-to-end. See README for what's done.

## 1. Tense / aspect / modality (`spec`)  — DONE (tense + perfect + progressive)
The reader maps the PARSIFAL aux SPEC node's features (pres/past/future, perf)
to `:tense`/`:aspect` on the clause IR (`spec-tense`/`spec-aspect`), and
`emit-clause` sets `concept-tense`/`concept-aspect` on the predicate concept.
NB: the formatter DOES render tense now, as an `@`-word on the predicate
(`[SEE:@PRESENT]`) — cgraph 74d0411 made the @-annotations survive a round trip.
It used not to ("consumed by the realizer"), so the older tests verify tense via
the `:tense` slot rather than the text; either works. "sees" -> :present,
"persuaded" -> :past (see live/coref headless tests).
**PROGRESSIVE — DONE 2026-09-04, both layers.** "the girl is eating pie ." ->
`[EAT: @present-progressive]`, and back through `say` as "The girl is eating a
pie." It did not parse AT ALL before this (found via `diagnose-parse`, §10): the
port had never registered Marcus's PROGRESSIVE rule, so with `is` in the buffer
BUILD-AUX fell through to AUX-COMPLETE, AUX-ATTACH dropped the aux, MAIN-VERB
took `is` ITSELF as the verb, and `eating` was left with no rule that accepts it.
(`be` is `auxverb` only in the dictionary; PASSIVE-AUX `[*be][en]` WAS registered,
which is why "a meeting is scheduled for friday ." parsed and no progressive did.)
- PARSER (parsifal): new `*progressive-rules*` group — `{RULE PROGRESSIVE IN
  BUILD-AUX [=*be] [=ing] --> Attach 1st to c as prog. Label c prog.}`, verbatim
  gram1:115 — in `*marcus-full-grammar*` (a restored Marcus rule, NOT an
  extension, so no EXTENSIONS.md entry). Disjoint from the other BUILD-AUX
  stackers by its second element, so they compose. Test
  `gram1-progressive-test` (incl. a guard that the sentence fails without the
  group, and that a passive is unaffected). `:core` deliberately left alone.
- EXTRACTOR: `spec-aspect` reads `prog` off the aux SPEC node -> `:progressive`;
  perf+prog (same node, both labels) -> `:perfect-progressive`, which cgraph's
  realizer also builds — though the surface form needs `been`, which Marcus's
  dictionary never entered, so it is unreachable today. Test
  `test/extract-progressive-headless.lisp` (slot + `@`-word + round trip +
  a perfect control for the mapping's other branch).

Still TODO here: modal (cgraph has no modal slot — needs a representation), and
voice (passive) beyond the participle case.

**COPULA is the remaining `be` gap** (same discovery, deliberately not done):
"the girl is happy ." still fails. Marcus's other unregistered BUILD-AUX rule is

    {RULE COPULA IN BUILD-AUX
     [=*be] [* is any of prep, adj; * is not part] --> Attach 1st to c as copula. …}

(`parsifal/notes/from-marcus/gram1.l` 136, `notes/pidgin-grammar-rules-1977.text`
125). Registering it is as small as PROGRESSIVE was, but the CG side is a real
design step, not a mapping: a predicate adjective/nominal is not a case role but
an `attr` link (or type subsumption) on the SUBJECT, so `emit-clause`'s
predicate-centred shape does not fit it. Do that deliberately, not as a follow-on.

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

PP ADJUNCTS (locative) — DONE (2026-07-07, extractor-only). The earlier claim
here was WRONG: a verb-unlicensed PP is NOT dropped. PARSIFAL attaches it to the
CLAUSE (the S node) as a surface `pp' daughter -- Marcus's own gram5 PP-UNDER-S-1
rule does `attach 1st to c as pp' even when the PP fits no case slot. The earlier
probe only checked VP and NP daughters and missed the S-level attachment. So this
needed NO grammar change (not a *grammar-extensions* rule): purely an extractor
gap. "the man sees the dog in the city ." ->
  [SEE]-(agnt)->[MAN: #] (obj)->[DOG: #] (loc)->[CITY: #].
EXTRACTOR (system/extract.lisp): clause-adjuncts walks the clause node's `pp'
daughters (pa::daughters 'pp) -- a licensed PP fills a case and leaves NO clause
pp daughter, so these are exactly the adjuncts; each -> {:prep :filler} on the
clause IR's :adjuncts; emit-adjunct maps the preposition via *preposition->
relation* (locatives in/on/at/near/... -> loc, ⊤->place) and emits
[PRED]-(rel)->[OBJ], reusing arc-dest-ok-p so a bad object type is skipped with a
warning. Test: test/extract-pp-adjunct-headless.lisp covers loc->[CITY] AND
inst->[TELESCOPE]. 21/21 headless; parsifal untouched (56/56).

NON-LOCATIVE PREPOSITIONS — DONE (2026-07-07): `with' -> inst (instrument, event
-> entity), so "the man sees the dog with the telescope ." ->
  [SEE]-(agnt)->[MAN: #] (obj)->[DOG: #] (inst)->[TELESCOPE: #]
-- exactly see's own canonical (inst)->[OBJECT]. This was a ONE-LINE add to
*preposition->relation* ("WITH" -> cg::inst); the clause-adjuncts/emit-adjunct
machinery from the locative work already handled it (the PP attaches to the S,
same as locatives -- verified). Also added `telescope' (⊑ tool) to CGRAPH
test-types (test/test-types/concept-types.lisp) so the strict test type-checks
(telescope was already in parsifal's supplement.dict). `with' is read as
INSTRUMENT not accompaniment: test-types have `inst' but no comitative relation,
and instrument is with's canonical adjunct sense. Extractor-only, no parser
change -> NOT in EXTENSIONS.md.
TEMPORAL PREPOSITIONS — DONE (2026-07-07): PP adjuncts route to the `time'
relation (situation -> time-period; see ⊑ act ⊑ event ⊑ situation), TWO ways --
(a) a dedicated temporal preposition (before/after/during/until/since,
*temporal-prepositions*), or (b) a time-NP object (PARSIFAL's `time' feature, e.g.
monday), which resolves the loc/time AMBIGUITY of in/on/at by the object's type:
  "the man sees the dog on monday ."     -> (time)->[MONDAY]  (ambiguous `on' + time obj)
  "the man sees the dog before monday ." -> (time)->[MONDAY]  (dedicated temporal prep)
  "the man sees the dog in the city ."   -> (loc)->[CITY]     (still locative)
New in extract.lisp: adjunct-relation(prep, obj) computes the relation (stored as
:relation on the adjunct IR); temporal-preposition-p + np-temporal-p. Added
`monday' (⊑ time-period) to cgraph test-types (monday is already a `time' noun in
parsifal's dict). Extractor-only, no parser change -> NOT in EXTENSIONS.md. Test:
extract-pp-adjunct-headless now covers loc + inst + time(obj) + time(prep). 21/21.
MANNER ADVERBS — DONE (2026-07-07): the SECOND grammar extension (after
apposition). "the man sees the dog quickly ." -> [SEE]...(manr)->[QUICKLY]. Needed
BOTH halves of an extension:
  - LEXICON (parsifal supplement.dict): quickly/slowly as `(df ... (adv manner))'.
    They were dropped as unknown; NB `df1' (Marcus's ago/later/very) is a DISABLED
    definition (expands to NIL), so plain `df' is required.
  - GRAMMAR (parsifal *adverb-rules*, our *grammar-extensions*): ADVERB-ADJUNCT IN
    SS-FINAL [=adv] -> attach the adverb as an `adv' daughter of the clause
    (modelled on gram5 PP-UNDER-S-1; default priority 10 beats VP-DONE at 20).
    gram1-gram5 have NO adverb-attachment rule, so without it the adverb stalls
    the parse.
  - EXTRACTOR (extract.lisp): clause-adverb-lemmas reads the clause's manner `adv'
    daughters; emit-clause emits [PRED]-(manr)->[MANNER] via emit-modifier
    (*adverb-relation* = manr), the adverbial analog of an adjective's
    [NOUN]-(attr)->[ADJ]. `quickly' isn't in test-types, so the test runs
    :create (QUICKLY under MANNER), like the adjective test's BIG under ATTRIBUTE.
Test: test/extract-adverb-headless.lisp. 22/22 headless; parsifal 56/56.
See parsifal EXTENSIONS.md entry #2. Documented in EXTENSIONS.md since it IS a
parser change (grammar rule + lexicon), unlike the extractor-only PP adjuncts.
DEICTIC adverbs (here/there -> loc, today/now -> time) -- DONE (2026-07-15),
extractor-only; see the DEICTIC banner at the top of this file.
STILL OPEN under #5: non-manner adverb classes (degree, etc.).

GENITIVES/POSSESSIVES (poss) — DONE (2026-07-01, parser + extractor). "the man's
dog" -> [DOG:#]<-(poss)<-[MAN:#]; also proper-name and pronoun possessors. See the
GENITIVES banner at the top of this file for the full write-up (parsifal
*genitive-rules* POSS-NP + POSSESSIVE-DET; extractor np-possessor/emit-possessor).
Still open under modifiers: adjective-class-specific relations.

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

## 7. PROPOSITION vs SITUATION for complements  — DONE
The complement wrapper type is now chosen from the clause FORM instead of always
being `proposition': a THAT-clause (THAT-S) is a statement -> [PROPOSITION: ...];
an INFINITIVAL (INF-S) is an event -> [SITUATION: ...]. clause-complement-form
reads the INF-S/THAT-S feature (it sits on the embedded S under the COMP-NP) into
the IR's :clause-type; complement-type-for maps it to *situation-complement-type*
(situation) vs *clausal-complement-type* (proposition), falling back to
proposition if the catalog lacks a graph-compatible `situation'. So:
  "the man knows that the boy sees the dog ." -> ...(stat)->[PROPOSITION:[SEE]...]
  "the boy wants to go ."       -> [WANT]-(agnt)->[BOY: #] (prop)->[SITUATION:[GO]...]
  "the boy seems to go ."       -> [SEEM]->(prop)->[SITUATION:[GO]->(agnt)->[BOY: #]]
  "the boy persuaded the girl to go ." -> ...(prop)->[SITUATION:[GO]...]
Relation interaction: the generic invented `prop' relation was widened to dest ⊤
(source ⊤, dest ⊤) so ONE relation links a predicate to either wrapper; the
stative `stat' (dest PROPOSITION) is now guarded to PROPOSITION complements only
(complement-relation-for takes the filler and skips `stat' for a :situation, so a
stative verb + infinitival wouldn't mis-type). New test contrasts the two forms
(test/extract-complement-headless.lisp); raising/coref/driver tests updated from
PROPOSITION to SITUATION (they use infinitival complements).

## 8. Coreference rendering `*x` vs `?x` (cosmetic)  — DONE (cgraph side + a leak fix)
Cross-context coreference now renders standard CGIF: the DEFINING occurrence is
`*x1` (the anchor) and the BOUND occurrence `?x1`, e.g.
  "the boy persuaded the girl to go ." ->
  [PERSUADE]-(agnt)->[BOY: #] (prop)->[SITUATION:[GO]->(agnt)->[GIRL:?x1]]
            (rcpt)->[GIRL:#*x1].
(previously both were `?x1`). Changes:
- cgraph system/core/coreference.lisp `coref-text': a defining-label concept
  renders `*label' WHEN it actually has a coreference partner ((coreference c) is
  non-nil); a LONE defining label with nothing referencing it stays `?label'
  (legacy) so `[cat: ?c]' round-trips and no dangling *anchor is emitted -- this
  keeps cgraph's own test-coref-formatting (lone ?j/?c) green with no test edits.
- cgraph system/core/concept.lisp `variable-text': suppress the `*var' when the
  concept ALSO carries a coref defining-label (coref-text owns the marker), fixing
  a pre-existing double-render ("*j?j" -> "?j"). Pure re-entrancy `*x' variables
  (no coref label) are unchanged.
- cg-from-parse system/extract.lisp `ir->cgraph': now calls
  cg::initialize-coreferences + cg::initialize-variables at the start of each
  extraction. Those caches are process-global in cgraph, so a label like X1 from a
  prior extraction leaked in and made a new X1 resolve to the STALE concept. The
  old `?x'/`?x' rendering masked this (both sides printed the same either way); the
  #8 `*x'/`?x' split exposed it -- surfaced as a cross-test failure in the headless
  suite. This is a real correctness fix, not just cosmetic.
extract-coref-headless.lisp updated to assert one defining `*x1' + one bound
`?x1'. Verified cgraph's test-coref-formatting/basic/nested still pass; all 18
cg-from-parse headless tests pass. NB the query-variable `*x' (wh-questions, the
separate *variables* system) is unaffected -- it never had a coref label.

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

## 11. Apposition: "the dog, Spot" -> [DOG: Spot]  — DONE (2026-07-07)
A standalone named individual only gets the BROAD type from the name's marker
(anim -> [ANIMAL: Fido], never [DOG: Fido]). To get the specific type, the head
noun supplies it via apposition: "the dog , spot ." -> [DOG: Spot]. WAS blocked
on the parser (PARSIFAL had no apposition grammar); fixed with a new PARSIFAL
rule (*apposition-rules*: APPOSITIVE IN NP-COMPLETE on [=apunc][=name], attaching
the name NP under the head's `appos' daughter while keeping the head's type) plus
a small extractor merge (np-appos-name -> :appos on the entity IR -> a NAMED
individual of the head's own type in emit-filler). This is the FIRST non-Marcus
grammar rule, so it lives in *grammar-extensions*. Works in subject and object
position. See the DONE banner at the top for the full write-up.

## 12. Anaphora (pronoun -> antecedent)  — PARTIALLY DONE (2026-07-15)
DONE: the narrow, binding-theory-safe slice -- a 3rd-person pronoun that is an
ARGUMENT (subject OR object) of an embedded that-complement corefers with the
MATRIX subject. Singular and plural.
  "the man knows that he sees the dog ." ->
    [KNOW]-(expr)->[MAN:#*x1] (stat)->[PROPOSITION:[SEE]-(agnt)->[MAN:?x1]
                                                          (obj)->[DOG:#]]
  "the woman knows that she sees the dog ." -> she = the woman (coref)
  "the man knows that the dog sees him ." -> him = the man (OBJECT pronoun)
  "the men know that the dog sees them ." -> them = the men (plural)
  "the man knows that he sees him ." -> he = the man, but him stays FREE (an
    embedded object is blocked when the embedded subject corefers with the same
    antecedent -- else he = him, violating Principle B in the embedded clause).
Extractor-only (no parser/cgraph change): PARSIFAL does NOT bind pronouns, so the
resolver lives in system/extract.lisp (anaphor-antecedent). It fires ONLY when the
pronoun is the subject of an embedded complement clause (clause-complement-form
non-nil) and the antecedent is the matrix subject -- so the pronoun is free in its
own clause and Principle B holds automatically ("the man sees him ." leaves `him'
an indexical: it is a co-argument of `the man'). A resolved pronoun becomes a
:trace bound to the matrix-subject node, and the EXISTING emit-trace machinery
realizes the coreference across the PROPOSITION context boundary as *x/?x, exactly
like a control trace (so no new emission code). Agreement gates it:
  - number + person (both must be 3rd-person; number-feature via PARSIFAL NS/NP);
  - GENDER clash blocks -- he/she demand male/female (*pronoun-gender*), the
    antecedent's gender is read from its cgraph type's canonical (sex) arc
    (lemma-gender scans canonical-graph-string for [MALE]/[FEMALE], checking
    [FEMALE] first since it contains MALE); unknown gender is permissive. So
    "the woman knows that he sees ..." leaves `he' indexical [PERSON: He].
Gated by *resolve-anaphora* (default T; NIL disables). Matrix verb is `know'
(KNOW is a cgraph test-type; `believe' parses identically but has no concept type).
Test test/extract-anaphora-headless.lisp (resolve he/she, gender-clash negative,
same-clause negative, no-pronoun control). Whole stack green: cg 25/25, all 4
suites PASS. Extractor-only, so NOT in parsifal EXTENSIONS.md.

STILL OPEN under #12 (each its own follow-up): multiple candidates with
salience/recency ranking (currently the only candidate is a subject);
antecedents other than a subject (e.g. matrix object, or a non-subject
NP); reflexives (not in the lexicon -- himself/herself dropped); and CROSS-sentence
anaphora (needs multi-sentence discourse, which we don't parse yet).
DONE 2026-07-15: object + plural pronouns (see the #12 banner above).
DONE 2026-09-14: GENITIVE POSSESSIVES ("John will drive his automobile to
Baltimore ." -> his = John), the resolver's second configuration -- same-clause,
subject antecedent, circularity-guarded. See the POSSESSIVE ANAPHORA banner above.

## 10. Ergonomic driver  — DONE
`cg-from-parse:parse-and-extract` (system/driver.lisp): string → cgraph graph.
`ensure-grammar` loads parsifal's clause-grammar.lisp + `load-full-grammar` once
(cached in *grammar-loaded*); one loaded grammar parses every supported
construction (verified across transitive/ditransitive/control/relative/adjective).
`:on-missing` keyword binds *on-missing-type*. Also `sentence->cg-text`. Exported
from the package. See test/extract-driver-headless.lisp.

**Parse-failure diagnosis** (2026-09-04): PARSIFAL is wait-and-see with no
backtracking, so a failed parse used to be a bare "could not parse". The parser's
globals still hold everything needed at the dead end, so `parse-failure-report`
reads them out — how the lexicon/morphology read each token (surface → root →
features, unknown words called out), which constituent nothing matched and where
it sits in the sentence, the active packets, the rules that fired, the rules that
COULD have fired in those packets (with the feature each is indexed under), and
the partial tree. `parse-and-extract` signals that report with its error;
`(diagnose-parse "…")` is the REPL entry point (on success it prints the surface
tree). "rules tested there: none" means the grammar has no rule for that
construction in those packets — a missing-rule diagnosis, as against a dropped
word. See test/extract-diagnose-headless.lisp.

## Upstream drift repairs (2026-09-04)
Five headless tests had gone red against sibling-repo changes — all cgraph moving
correctly and this layer not following. Recorded because the *shape* recurs:
- **`has-part` → `part`** (cgraph 32a1db3, 2026-08-01: the general mereology
  relation took the short name, the physical-object one became `physical-part`).
  The exchange frame emitted `has-part`, so every exchange extraction died with
  `relation-type-lookup-failed`, and `validate-ontology` required a relation the
  catalog no longer had. Followed the rename in `emit-exchange`,
  `*ontology-requirements*`, render.lisp's comments and the tests.
- **`prop` lost its realizer syntax** (cgraph e05fe91): cgraph's lint found
  `(prop :dobj)` in `*relation-syntax-table*` naming a relation no shipped catalog
  defines and dropped it — true of cgraph, false of us, since
  `ensure-complement-relation` INVENTS `prop`. An unmapped relation is dropped
  silently by the realizer, so `sentence->say` lost every non-stative complement
  ("the boy wants to go" → "The boy wants." again — the same symptom as the
  2026-07-15 fix, a different cause). Fix: `ensure-complement-relation` now also
  calls `cg::register-relation-syntax` — the hook cgraph provides for an ontology
  teaching the realizer a relation it has never heard of. Lesson: a self-provided
  relation must self-provide its SYNTAX too, or it is mute in generation.
- **Referent rendering** (cgraph f81c7c9 + 74d0411): a generic collection is now
  `{*}`, distinct from `{}` (the empty/unquantified set), and the formatter emits
  the `@`-word annotations, so every predicate shows its tense. Two tests asserted
  the old strings; one also tested the whole graph text for "no `@`" and now found
  the verb's tense. Test-side fixes, anchored to the concept under test.

Both repos were right; only this layer was stale. The whole-stack gate
(`test/run-all-suites.sh`) is what makes that visible — run it after any sibling
change, not just after a change here.

## Cross-cutting notes
- Tests load the controlled **test-types** catalog non-destructively via
  `test/test-setup.lisp` (binds `*cgraph-types-directory*`, never repoints the
  `~/.cgraph/types` symlink). PARSIFAL dict has boy/girl/dog/man/person/see/give/
  hit/meet but NOT eat/cake.
- Out-of-ontology lemmas: `*on-missing-type*` (:error / :create / :top).
- Headless run recipe is in each `test/extract-*-headless.lisp` header.
- **Scoping the pipeline** — two composable scope surfaces: parsifal GRAMMAR
  PROFILES (`load-grammar`/`register-grammar-profile`; a restricted profile REJECTS
  out-of-scope input) and the cg-from-parse ONTOLOGY CONTRACT
  (`*ontology-requirements*` + `validate-ontology`; the framework types/relations a
  mounted ontology must provide, attributed per construction so it composes with a
  grammar profile). Design doc: `notes/scoping-and-ontology-contract.md`. Both hooks
  are in; next step that exercises the pair is a first real `:core` profile.
