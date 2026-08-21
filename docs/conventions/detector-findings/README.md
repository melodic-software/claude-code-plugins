# Detector findings — reaching the apply relay from outside `review:fanout`

Owner doc for **how a component that is not `review:fanout` persists findings that the fanout `fix`
action will consume**. One rule: a producer writes a file conforming to the findings-file shape into
the current branch's findings directory, and nothing else. No fanout edit, no registration, no
dispatch wiring.

The shape is owned by
[`plugins/review/skills/fanout/context/default-mode.md`](../../../plugins/review/skills/fanout/context/default-mode.md)
"Findings-file shape (stable contract — the fix action consumes it)". **This doc never restates it.**
What this doc owns is everything the shape alone does not settle: which fields a non-fanout producer
must compute for itself, what coexistence between producers means, and where the boundary sits.

It was published as a stub ahead of its depth, on `PLUGIN-PHILOSOPHY.md`
[Convention registry](../../PLUGIN-PHILOSOPHY.md#convention-registry) — "A new cross-plugin
convention lands in an owner doc **before a second plugin adopts it**" — which is a deadline rather
than a licence to author late. The depth below is the first detector pilot's evidence, and the
crosswalk is written from it: a rule whose tier cannot be argued from `severity.md`'s test is not
admitted, which is a bar no table of thresholds can clear on its own.

## Why the contract is format-only

Nothing authenticates the writer. The `fix` action locates its input purely by frontmatter — files
declaring `type: review-findings` whose `branch:` matches the current branch exactly — never by
provenance. That is not an oversight and it is the cheapest wiring path in the fleet: a skill, a
script, a hook, or an agent all reach the apply relay by writing one file.

It matters because the fleet's gap is **detectors, not apply capability**. Deterministic detectors
exist and produce real findings; what they lack is a route to a remediation surface. Conforming to a
file format is that route.

## Where the file goes

The destination is a **memory-tier, concern-scoped** location, and a producer resolves it through the
same binding the consumer does:
[`plugins/review/reference/topic-docs.md`](../../../plugins/review/reference/topic-docs.md)
"Resolution (the contract's five-rung order, earlier wins)", which
[`SKILL.md`](../../../plugins/review/skills/fanout/SKILL.md) "Shared inputs" names as what
`review:fanout` resolves through. `SKILL.md` itself does not restate the ladder — it points at
`topic-docs.md` and warns against assuming its shape, so a producer and the consumer read one text
rather than two that have to be reconciled. Naming the
binding by its repo path is the point of this section: `review:fanout` reaches it through a
`${CLAUDE_PLUGIN_ROOT}`-relative pointer no plugin outside `review` can expand, and it is the same
document either way.

What the binding leaves to a producer — consequences, not a second statement of its rules:

- **Run the rung order, not only its last rung.** Writing to the documented default when a higher
  rung resolved puts the file somewhere the `fix` action never scans, and nothing reports the miss —
  the configured `memory_dir` and the `CLAUDE.md`-declared location are exactly the cases that fail
  silently.
- **Take the non-interactive collapse.** A producer that cannot ask the user or persist config — a
  headless detector cannot — resolves the rungs that confirm or ask through the
  [topic-docs convention](../topic-docs/README.md) "Non-interactive / forked mode". Inventing an
  answer to those rungs instead resolves to a directory the consumer never reaches.
- **The directory never proves ownership.** What proves a file is this branch's is its own `branch:`
  frontmatter, never the directory it sits in — the binding's slug rule says why.
- **The self-ignore guard is owed, not re-derived** — including the convention's invalid cases, which
  stop the guard from healing into a consumer's root `.gitignore` and from writing at a root no
  checkout is detected as governing. Skipping it **where a checkout governs the destination** commits
  findings that are meant to stay checkout-local. Where none is detected the convention's own rule is
  that the guard does not run. **The artifact write is not automatically safe there either**:
  recreating a path that is an *index-tracked deletion* in a missed checkout modifies tracked state
  rather than creating an untracked one (measured), so "it lands untracked" is not universally true.
  But a blanket refusal is the wrong correction — it would refuse the `${CLAUDE_PLUGIN_DATA}`
  fallback the convention routes non-interactive runs to, which sits outside every checkout **by
  construction** and cannot be a tracked deletion. The rule follows that distinction: write where the
  destination is that plugin-data surface, and where it is a resolved root no checkout could be shown
  to govern, report the resolved destination and persist nothing.

## Boundary

This doc owns the **producer-side contract** for non-fanout findings. It does not own:

- **The findings-file schema.** Owned by `default-mode.md` "Findings-file shape". Pointer, never a
  copy — a second statement of a table is a second thing to drift.
- **The consumer algorithm.** How the merge set is built, subtracted, deduplicated, and applied is
  owned by
  [`plugins/review/skills/fanout/context/fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md)
  "Step 1: Build the merge set". A producer never needs to read it; it is named here so a reader
  chasing consumption behavior lands in one place.
- **Normalization and ranking.** The five-stage pipeline in
  [`findings-normalization.md`](../../../plugins/review/skills/fanout/context/findings-normalization.md)
  is fanout's own internal reduction. A detector emits final values, not pipeline inputs.
- **Whether a detector should exist.** Candidate selection, guardrail class, and promotion are the
  `autonomy` plugin's routine-catalog concern.
- **Findings that never reach a relay.** A component that only reports to a human is out of scope;
  this contract begins at the decision to persist.

## The four producer-owned fields

A detector has no severity crosswalk, no confidence filter, and no normalization stage behind it.
These four are therefore computed by the producer, and each has a failure mode that is silent:

1. **`Tier` is LOOKED UP from the rule, never chosen per finding.** Read it off the rule's row in
   [the severity crosswalk](#the-severity-crosswalk) below, so every finding of a rule carries that
   rule's tier. A detector picking a tier per run makes rank order meaningless across runs. Note what
   this does and does not promise: the lookup is fixed, while *which rule a candidate selects* may
   itself be a judgment — see the crosswalk's admission test, which is where that is bounded. The
   **vocabulary** is not this doc's to define: it is owned by
   [`plugins/review/context/severity.md`](../../../plugins/review/context/severity.md) "Severity
   tiers", whose consumer-precedence rule binds a producer too — when the consuming project defines
   its own severity vocabulary, map to the project's tiers rather than the baseline's. A detector
   emitting a vocabulary of its own invention is non-conforming.
2. **`Confidence` is `high` or OMITTED — never `low`.** The enum is defined by
   [`severity.md`](../../../plugins/review/context/severity.md) "Confidence axis", which already
   states the trap — `unscored` means "absence of a score is NOT low confidence". The *consequence*
   is what makes `low` actively harmful: the rank order is `high` > `medium` > `unscored` > `low`
   ([`findings-normalization.md:72`](../../../plugins/review/skills/fanout/context/findings-normalization.md)),
   so emitting `low` to express uncertainty ranks the finding *below* saying nothing at all. A
   deterministic detector that fired is `high`; anything less certain omits the field.
   **`Confidence` is confidence-of-realness, not confidence in the fix.** A detector can be certain a
   defect is real while its remediation needs human judgment; say that in `Tier` and in the `Action`
   wording, never by downgrading `Confidence` — that would bury a real finding beneath one nobody
   reported.
3. **`Location` is a repo-relative `file:line`.** The relativization rule is stated by
   `default-mode.md` "Findings-writer contract". What is producer-specific is the reason it is
   not optional: the fix action fences each remediation to its finding's `Location`, and an absolute
   path is not portable to the checkout that applies the fix.
4. **Cell escaping is the producer's job.** Apply `default-mode.md`'s "Cell-escaping rule (required —
   the fix action parses this table)" as written there. It is called out here, without restating the
   characters, because detector output routinely contains pipes — shell pipelines, type unions, regex
   alternation — making this the single most likely way a first detector ships a file that parses
   *wrong* rather than not at all.

## Rule ids and thresholds

A `Tier` nobody can re-derive is a `Tier` nobody can audit. Two obligations make it re-derivable from
the emitted file alone, without re-reading the detector:

- **A rule id is `<plugin>/<skill>/rule-<slug>`**, lowercase `[a-z0-9-]` in each segment. **One form,
  everywhere** — the crosswalk's own column, the emitted `Finding` cell, and any prose. There is no
  short form: this crosswalk is a cross-producer registry, so an unqualified id in it would be a
  collision waiting for the second detector, and the gate this enables (Enforceability, below)
  resolves an emitted id against a row by exact match. Qualification makes that resolution correct by
  construction rather than by a uniqueness rule nothing enforces. The `rule-` segment is kept so the
  id stays self-identifying wherever it appears.
- **Every emitted row leads its `Finding` cell with that id and the threshold that fired.** No column
  is added — the shape is not this doc's to change — and the leading position is what keeps the id
  greppable without one.
- **The threshold is the condition that fired in the run's own values**, not the rule's definition
  restated. `depth 7, limit 5` is auditable; `over the limit` is not.

**The id shares its shape with — but is not identical to —
[`finding-suppression`](../finding-suppression/README.md)'s `check:` constituent**, which that
contract hashes into a `finding_id`. The two compose because they are built the same way, and a
consumer may legitimately qualify checks at a **finer** granularity than the rule: the first adopter
keys a suppression `check:` to the mutation operator, because a suppression retires per mutant while
a crosswalk rule classifies a disposition. Do not assume a `check:` value is a rule id.

## The severity crosswalk

**Rule id to tier, with the test each mapping is argued from.**
[`severity.md`](../../../plugins/review/context/severity.md) "Severity tiers" decides a tier by test,
first match winning, and says outright that resemblance to an illustrative finding is not that
argument. A bare threshold cannot evaluate those tests — a number is not an input to "you can name a
concrete input, caller, or subsequent otherwise-correct change that the defect makes produce a wrong
result" — so a threshold-to-tier table with no argument in it is nominal closure. **The argument is
the row.**

**What this table makes deterministic is the MAPPING, not the input.** Given a rule id, the tier, the
disposition and the auto-applicability are fixed here and are never re-derived per finding — which is
the failure the contract names, a detector picking a tier per run out of the finding's prose. It does
**not** claim that the same tree always selects the same rule, and for at least one admitted producer
it demonstrably does not: `mutation-testing:audit` classifies each survivor through a fresh-context
reviewer, and `SKILL.md` "Phase 4" says plainly that the difference between its classes is a
judgment. Saying otherwise here would be the same defect this table exists to catch, one level up.

Admission test for a crosswalk row:

1. **The mapping is fixed and published** — the row states it, and the producer looks it up rather
   than deciding it.
2. **A rule set whose selection involves judgment is fail-safe toward EMITTING.** Selection may be a
   judgment; what may not vary is which way an unresolved one falls. Every non-emitting rule states
   the positive evidence its selection requires, and absence of that evidence selects an **emitting**
   rule. That is what bounds the cost of a judgment: it can move a finding between emitting rules or
   make a run noisier, but it can never silently withhold one. **Check it on EVERY withholding
   boundary, not the one that is easiest to argue** — the pilot's set has two, and its second was
   admitted with the bar stated only on the first, which is exactly how a criterion passes on a
   worked example while leaving the gap it was written for open. Both now fall through to
   `mutation-testing/audit/rule-survivor-unclassified`, which emits at IMPORTANT. A rule set where
   an unresolved judgment falls toward silence is not admitted, whatever its rows argue.

   **The fall-through must take effect before the producer's FIRST output.** This binds an outcome —
   one candidate gets one disposition on **every** surface the producer emits to — and deliberately
   not a structure: a producer with a single output surface satisfies it by construction and owes no
   separate classification step, phase, or bar of any named shape. What fails it is a producer with
   more than one surface applying the fall-through on the path to only some of them, so a human
   reading one artifact and the relay reading another are told different things about the same
   candidate. The pilot hit exactly that — its report is written before its findings file, so a bar
   placed at persist time would have said "arid" in one and "unclassified" in the other — and that
   is why its bar sits at classification. **The placement is the pilot's answer, not the rule.**

   The bar this reaches is **instruction-strength, not mechanism-strength**: the fall-through is
   stated imperatively and no gate computes whether a cited demonstration is real. Saying so is the
   point — a criterion that claimed more than the mechanism delivers would be the failure this
   contract is about.
3. **An emitting rule argues its tier in the row from `severity.md`'s tests, first match winning.** A
   rule that emits **no** row argues instead that its finding never reaches the relay — the
   Boundary's "Findings that never reach a relay" case, which sits outside the tier vocabulary
   entirely. The two grounds are not interchangeable, and a non-emitting row must say which it is
   using: reaching for a tier test to justify a non-emission is how a row looks argued while arguing
   nothing, because a tier test can only ever return a tier.
4. Its auto-applicability is settled here rather than per finding at apply time (below).

**A rule failing 3 is not a row with a missing cell — it is a rule this contract does not admit**,
and its detector reports to a human instead, which is the same Boundary case reached from the other
side.

| Rule id | What fires it | The test the disposition is argued from | Tier or disposition | Auto-applicable |
|---|---|---|---|---|
| mutation-testing/audit/rule-survivor-productive | A surviving mutant classed productive — its survival demonstrates a gap in what the suite asserts | CRITICAL's test is that you can name a concrete input, caller, or subsequent otherwise-correct change that the defect makes produce a wrong result, an unsafe one, or none at all. A survivor satisfies no limb: it is evidence that the suite fails to detect a change, not that anything produces a wrong, unsafe or absent result. The third limb is the near miss and still fails, because the defect it needs is one in the source while a survivor is evidence about the tests. IMPORTANT's second limb then matches — behavior the change ADDS that no test covers — and the "adds" clause is satisfied because this producer is diff-scoped, so the mutated node is inside the change under review. | IMPORTANT | No — the remediation is the covering test, not `Location` |
| mutation-testing/audit/rule-survivor-unclassified | Any non-emitting verdict — equivalence OR aridity — claimed without the positive evidence its own rule requires. This is the fall-through both withholding rules land in, which is what makes them fail-safe rather than silent. | The tests are evaluated against what the run demonstrated, never what it asserted. With no evidence the run has shown exactly what the productive rule shows — a mutant survived inside the diff — so IMPORTANT's added-behavior-no-test-covers limb matches on identical facts. Admitting a lower tier on an undemonstrated assertion would let the assertion decide the tier instead of the test, which is the standard way this technique manufactures false confidence. | IMPORTANT | No — same off-site remediation |
| mutation-testing/audit/rule-survivor-arid | **Aridity demonstrated**: the proposed suppression entry is complete (all five keys, id derived from them), its claim names a node kind from the producer's enumerated vocabulary, and its reason names the specific behavior the suite deliberately does not assert on. "Killing this would not improve the suite" asserted from inspection is not that demonstration. An arid call that cannot show it is not arid — it selects the unclassified rule above, which emits. | Argued from the Boundary, NOT from a tier test, and the row says so because the tier tests do not decide it: applied literally, IMPORTANT's added-behavior-no-test-covers limb WOULD match an arid survivor and first-match-wins would land on IMPORTANT. What withholds the row is that its only remediation is a suppression entry an operator must accept, so the finding never reaches the relay at all — the Boundary's "Findings that never reach a relay" case. Handing a consent-gated write to an apply relay would launder that gate. | No row — proposed suppression | Not applicable — no row |
| mutation-testing/audit/rule-survivor-equivalent | Equivalence demonstrated: identical observable behavior across the differential cases the rule names, with the mutated state shown dead or idempotent | Argued from the Boundary, not from a tier test — and not by claiming the tests are unreachable, because SUGGESTION is a catch-all ("neither test holds") that any finding can reach. The ground is that every tier presupposes a defect to act on and a demonstrated equivalent mutant is not one: no behavior changed, so nothing failed to detect it. Being not a finding, it never reaches the relay; emitting a row would manufacture one. | No row — declined candidate | Not applicable — no row |
| testing/audit/rule-zero-assertion | A runnable test body containing zero assertion tokens (threshold: 0). Selection is a mechanical token scan with no withholding verdict, so the fail-safe criterion is met by construction. The one decline is evidence-stated: an in-file `cant-fail-ok: <reason>` annotation marks a deliberate case, which is declined at selection and counted in `## Surfaces` — never silently dropped. | CRITICAL's test fails on every limb: a test that cannot fail makes nothing produce a wrong, unsafe, or absent result — it is evidence about the suite's oracle, not about the source, and the third limb's subsequent-change clause needs a source defect this finding does not assert. IMPORTANT's degradation-with-a-named-trigger limb then matches: the test's existence is a coverage claim nothing backs, and the trigger is nameable — the first regression in the behavior this test exercises ships under a green run. First match wins there. | IMPORTANT | No — contained to `Location`'s file, but the repair encodes the intended oracle (which assertion the behavior deserves), a call for judgment Step 4 surfaces rather than auto-applies |
| testing/audit/rule-recomputed-expectation | An equality assertion whose actual and expected sides are the identical expression, so the expected value is recomputed by the code under test rather than stated (threshold: at least 1; v1 detects the decidable core — textually identical sides). Mechanical selection, no withholding verdict; the `cant-fail-ok:` decline evidence above applies identically. | Same first-match walk as the zero-assertion row: CRITICAL fails every limb because the assertion holds for every implementation of the expression — no input, caller, or subsequent otherwise-correct change can make it produce a wrong result, the oracle being the defect. IMPORTANT's degradation limb matches with the same named trigger: a regression in the recomputed expression's behavior passes green. | IMPORTANT | No — same contained-but-oracle-judgment repair as the zero-assertion row |
| testing/audit/rule-mock-only-oracle | A mock-constructing test whose every recognized assertion is a mock-interaction assertion, none on a real collaborator (threshold: 100%). Selection is mechanical; what is uncertain is defect-hood — a deliberate interaction-style test is the known benign case. That uncertainty resolves TOWARD emitting: the row is emitted with `Confidence` omitted (the high-or-omitted rule), never withheld, so this rule needs no fall-through. The `cant-fail-ok:` decline evidence above is how a deliberate case is recorded. | CRITICAL's test fails every limb — the test can still fail (an interaction change fails it), and nothing produces a wrong result; what is defective, when it is, is that the oracle restates the implementation's interactions. IMPORTANT's degradation limb matches: a behavioral regression in the real collaborator ships green while the interactions hold, and that trigger is nameable. The benign-case uncertainty lives in `Confidence` and the consumer's gating, never in the tier — a per-finding tier drop is exactly what a rule-keyed map forbids. | IMPORTANT | No — contained to `Location`, but choosing the real-collaborator oracle over the interaction contract is design judgment; Step 4 surfaces it |
| ai-slop/audit/rule-em-dash | An em dash in prose outside code fences, inline code, in-file ignore markers, and config-declared exempt documents (zero-tolerance: any occurrence; per-document exemption only, never a threshold). Selection is a byte-sequence scan with no withholding verdict, fail-safe by construction; declines carry stated evidence (marker, config path, code fence) and are counted per rule in `## Surfaces`. | CRITICAL fails every limb: prose punctuation makes no input, caller, or subsequent change produce a wrong result. IMPORTANT fails: the shipped default names no stated rule of the consuming repo, and a style tell has no degradation trigger to name — a repo that declares a no-em-dash rule is enforcing its own convention through config, which does not move the baseline tier. SUGGESTION's test holds: a preference among alternatives that all work. | SUGGESTION | No, remediated by `/ai-slop:audit fix` — the repair rewords the sentence (comma, colon, period, or restructure), a judgment call, not a mechanical swap |
| ai-slop/audit/rule-emoji-formatting | An emoji in formatting position (line start, heading lead, or list-marker lead) on a prose line, outside the exempt contexts above. Mechanical selection, no withholding verdict; same counted decline evidence. | Same walk as rule-em-dash: no wrong result (CRITICAL fails), no stated baseline rule or nameable degradation trigger (IMPORTANT fails), a formatting preference among working alternatives (SUGGESTION holds). | SUGGESTION | No, remediated by `/ai-slop:audit fix` — removing a formatting emoji changes the line's structure; the repair is a small rewrite, not a strip |
| ai-slop/audit/rule-curly-artifacts | A curly quote, curly apostrophe, zero-width space, or no-break space in prose (chat-interface paste residue), outside the exempt contexts above. Mechanical byte-class selection, no withholding verdict; counted declines. | No wrong result is producible from typography bytes (CRITICAL fails). IMPORTANT fails at baseline: whether straight quotes are the rule is the consuming repo's convention, not this contract's, and no degradation trigger attaches to a rendered curly quote. SUGGESTION holds: a preference between typographic and typewriter punctuation, both of which work. | SUGGESTION | No, remediated by `/ai-slop:audit fix` — most swaps are mechanical, but apostrophes inside contractions and deliberate typography make the safe form a reviewed edit |
| ai-slop/audit/rule-significance-inflation | A stock significance phrase ("stands as a testament", "pivotal moment", "reflects broader", "evolving landscape", and the catalog's list) on a prose line, outside the exempt contexts above. Mechanical phrase-list selection, no withholding verdict; counted declines. | The phrase asserts importance, it does not compute anything: CRITICAL fails every limb. IMPORTANT fails: no stated rule, and inflated register carries no nameable degradation trigger. SUGGESTION holds — plain statement and inflated statement both function; the finding is a register preference backed by the source catalog. | SUGGESTION | No, remediated by `/ai-slop:audit fix` — the repair deflates a claim, which changes what the sentence asserts; semantic judgment, never auto-applied |
| ai-slop/audit/rule-negative-parallelism | A "not just X but Y" or "isn't X; it's Y" construction on a prose line, outside the exempt contexts above (the source's third pattern, "X rather than Y", is deliberately not selected in V1 — too common in ordinary prose; recorded in the catalog). Mechanical selection, no withholding verdict; counted declines. | A rhetorical construction produces no wrong result (CRITICAL fails). No stated rule or degradation trigger (IMPORTANT fails). SUGGESTION holds: the construction and its plain restatement both work; the finding is a register tell. | SUGGESTION | No, remediated by `/ai-slop:audit fix` — collapsing the parallelism is a rewrite of the sentence's emphasis; judgment |
| ai-slop/audit/rule-challenges-conclusion | The outline-formula conclusion ("Despite its X, faces challenges", "challenges remain/ahead") on a prose line, outside the exempt contexts above. Mechanical selection, no withholding verdict; counted declines. | No computation, no wrong result (CRITICAL fails); no stated rule or nameable trigger (IMPORTANT fails); SUGGESTION holds — the formula and a substantive close both work, and the finding is the formula. | SUGGESTION | No, remediated by `/ai-slop:audit fix` — replacing a formulaic close requires writing an actual conclusion; judgment |
| ai-slop/audit/rule-knowledge-cutoff-disclaimer | An assistant-frame provenance phrase ("as of my knowledge cutoff", "as of my last update", "as an AI model") in committed prose, outside the exempt contexts above. Mechanical phrase selection, no withholding verdict; counted declines — the known benign class (prose ABOUT model cutoffs) is recorded in the catalog's calibration record and declines only via marker or config with that stated evidence. | CRITICAL fails: the sentence computes nothing. IMPORTANT's degradation limb matches with a named trigger: the disclaimer asserts a provenance and freshness caveat that is false of the committed document, and the trigger is the first reader who acts on the caveat as if it governed the document (treating current content as stale or unverifiable). The cost is reader-facing degradation of the document's authority, not a preference between working alternatives, so the SUGGESTION catch-all is never reached. | IMPORTANT | No, remediated by `/ai-slop:audit fix` — the repair usually deletes the sentence, but deciding whether surrounding prose depended on it is a read |
| ai-slop/audit/rule-llm-citation-artifacts | Model-internal citation residue (`oaicite`, `[cite:`, `grok_card`, `attached_file`, `contentReference`, `filecite`) in prose, outside the exempt contexts above. Mechanical fixed-string selection, no withholding verdict; counted declines. | CRITICAL fails: broken reference text computes nothing and breaks no caller. IMPORTANT's degradation limb matches with a named trigger: the residue renders as a dangling reference token where a citation was meant to be, and the trigger is the first reader chasing the reference the token pretends to be — reader-visible breakage, not a style preference, so SUGGESTION is never reached. | IMPORTANT | No, remediated by `/ai-slop:audit fix` — deleting the token leaves the claim uncited; whether to drop, replace, or source the citation is judgment |
| ai-slop/audit/rule-utm-params | A `utm_*=` tracking parameter inside a URL in prose, outside the exempt contexts above. Mechanical selection, no withholding verdict; counted declines. | CRITICAL fails: the link resolves identically without the parameter, so no wrong result is producible — which is also the auto-applicability argument. IMPORTANT fails: no stated rule, and the maintenance cost has no nameable trigger (the link works). SUGGESTION holds: URL with and without tracking both work; stripping is hygiene. | SUGGESTION | Yes — contained to `Location`, and the strip is meaning-preserving by the same argument that fails CRITICAL: the URL's resolution is unchanged |
| ai-slop/audit/rule-ai-vocabulary | AI-vocabulary density at or above the effective threshold (default 3.0 matches per 1000 words, minimum 3 matches; word list config-tunable) in a file's prose, outside the exempt contexts above. The fired condition carries the run's own values (density, threshold, hits, words). Mechanical selection, no withholding verdict; counted declines. | Word choice produces no wrong result (CRITICAL fails). No stated baseline rule, no degradation trigger (IMPORTANT fails). SUGGESTION holds: every listed word has a working plain alternative; the finding is a distributional register tell from the source catalog. | SUGGESTION | No, remediated by `/ai-slop:audit fix` — replacing vocabulary requires choosing each replacement in context; judgment |
| ai-slop/audit/rule-copulative-avoidance | Copulative-substitute density ("serves as", "functions as", "represents a", and the catalog's list) at or above the effective threshold (default 4.0 per 1000 words, minimum 3 matches), same exempt contexts and fired-condition form as the vocabulary rule. Mechanical, no withholding verdict; counted declines. | Same walk as rule-ai-vocabulary: no wrong result, no stated rule or trigger, a register preference between "serves as" and "is" where both work. SUGGESTION holds. | SUGGESTION | No, remediated by `/ai-slop:audit fix` — same in-context replacement judgment |
| ai-slop/audit/rule-rule-of-three | Triplet-construction density ("X, Y, and Z" patterns) at or above the effective threshold (default 3.0 per 1000 words, minimum 3 matches — the floor added by calibration after single-triad short files fired), same exempt contexts and fired-condition form. Mechanical, no withholding verdict; counted declines. | A rhetorical cadence produces no wrong result (CRITICAL fails); no stated rule or nameable trigger (IMPORTANT fails); SUGGESTION holds — triads and varied sentence shapes both work; the finding is cadence monotony evidence from the source catalog. | SUGGESTION | No, remediated by `/ai-slop:audit fix` — breaking a triad rewrites the sentence; judgment |
| ai-slop/audit/rule-chatbot-artifacts | A chat-turn or sycophancy phrase ("I hope this helps", "let me know if you", "great question", "you're absolutely right", and the catalog's list) on a prose line, outside the exempt contexts above. Mechanical phrase selection, no withholding verdict; counted declines. | CRITICAL fails: a stray chat phrase computes nothing and breaks no caller. IMPORTANT's degradation limb matches with a named trigger, on the same walk as rule-knowledge-cutoff-disclaimer's: the phrase asserts a conversational exchange that is false of the committed document — there is no chat partner to "let know" — and the trigger is the first reader who takes the document as an unedited assistant transcript and discounts its authority accordingly. Reader-visible generation residue, not a preference among working phrasings, so the SUGGESTION catch-all is never reached. | IMPORTANT | No, remediated by `/ai-slop:audit fix` — the sentence usually deletes, but chat residue can carry real content ("let me know if the retry loop misbehaves") that must survive in document register |
| ai-slop/audit/rule-filler-phrases | A multiword filler phrase with a shorter exact equivalent ("in order to", "due to the fact that", "it is important to note that", and the catalog's list) on a prose line, outside the exempt contexts above. Mechanical phrase selection, no withholding verdict; counted declines. | Filler wording produces no wrong result (CRITICAL fails every limb). IMPORTANT fails: the shipped default names no stated rule of the consuming repo, and verbosity carries no nameable degradation trigger. SUGGESTION holds: "in order to" and "to" both work; the finding is a concision preference from the source catalog. | SUGGESTION | No, remediated by `/ai-slop:audit fix` — the word swaps are near-mechanical, but the deletable phrases ("it is important to note that") change sentence emphasis when removed |
| ai-slop/audit/rule-stacked-hedging | Two stacked hedges in one phrase ("could potentially", "might possibly", and the catalog's list) on a prose line, outside the exempt contexts above. Mechanical phrase selection, no withholding verdict; counted declines. | A doubled hedge produces no wrong result and weakens no caller (CRITICAL fails). IMPORTANT fails: no stated rule, and redundant hedging has no nameable degradation trigger — the claim's uncertainty is stated either way. SUGGESTION holds: one hedge and two hedges both express the uncertainty; the finding is a redundancy preference. | SUGGESTION | No, remediated by `/ai-slop:audit fix` — choosing which hedge states the real uncertainty is a claim-strength judgment |

The map is flat across the emitting rules on purpose — within each producer's set every emitting rule
makes the same claim, so every emitting row of that producer carries the same tier. A spread would
have to come from the finding's prose, which is what a rule-keyed map exists to prevent. A spread
that comes from the RULES is a different thing and is admitted: `ai-slop:audit`'s set carries two
claims — style preference (SUGGESTION) and reader-visible generation residue (IMPORTANT) — and each
row argues which claim its rule makes, so the tier still never varies per finding.

**Consumer precedence binds the crosswalk, not only the vocabulary.** `severity.md` is the fallback
baseline and a consuming project's own severity vocabulary overrides it, so the tiers above are
baseline values a producer maps away from when the project defines its own. This repository's
[`REVIEW.md`](../../../REVIEW.md) "Severity" is the live instance, and it shows the mapping is not a
formality: it resolves to the same three names but folds Critical and Important onto a single marker,
so the tier name alone does not survive. **The row's argued test does** — a reader holding it can
re-derive which side of the fold a finding sat on. That is the second reason the argument belongs in
the row rather than in a footnote to it.

## When the remediation is not at `Location`

`Location` names the **detection** site, always, and is never retargeted at the remediation. The key
that collapses two producers' rows into one is identical `Location` plus identical `Finding`
([`fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) "Step 2"), so
retargeting destroys the row's identity — and it asserts the detector fired somewhere it did not.

Detectors whose fix site differs from their detection site are ordinary rather than exotic: a
surviving mutant is fixed in its covering test, a missing test for a changed function is written
elsewhere, a contract violation detected at a caller may belong to the callee.

- **Producer obligation.** A rule whose remediation can lie outside `Location`'s file says so in its
  crosswalk row's auto-applicable cell, and every row it emits **names the remediation target in
  `Action`**. The producer already knows the target; withholding it is pure loss.
- **Consumer disposition.** `fix-pass-mode.md` "Step 4" surfaces such a row instead of auto-applying
  it — a named trigger of that step's own escape clause, added there rather than described here.

The trigger is what makes the producer obligation safe. Before it existed, a fixer reaching one of
these rows had no disposition the contract offered: Step 4 fences each fix to `Location` while the
`Action` cell named a different file, leaving it to breach its fence or invent a reason to surface.
Naming the target could not fix that by itself — it turned an ambiguity into an explicit instruction
to violate the governing rule.

**A remediation-target column was considered and rejected.**

- It changes a shape every producer writes and every consumer parses, to serve a minority of rows.
- What it would enable is an unattended two-file apply, which is precisely what the fence forbids. A
  column that made such an apply fenceable would have to carry the edit plan, not a path.
- The verdict is already reachable without it: Step 4 auto-applies only contained fixes, and a
  cross-file remediation is not contained by construction. The column would add structure to reach a
  conclusion the existing criterion already reaches.

## When the remediation is owned by the producer's own skill

A remediation can sit exactly at `Location` and still not be the consumer's to apply. The rewrite is
contained to one file and one line, and what makes it safe is a body of discipline the **producer**
owns — replacement forms, a plain-speech target, a semantic-diff guard — which lives in that
producer's own reference material and reaches no consumer through the findings file. The relay is not
withholding that discipline by oversight: nothing in the contract ever told it the discipline exists.

**The off-site disposition above does not reach this case, and neither does `Auto-applicable: No`.**
Both were checked before this section was written, because a third disposition an existing one
already covers is pure cost.

- **Off-site is a statement about the SITE.** Its producer obligation binds "a rule whose remediation
  can lie **outside `Location`'s file**", and the consumer's trigger
  ([`fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) "Step 2") has
  two limbs that are both site limbs: the `Action` names a different file, or the producing
  detector's contract declares the rule off-site. A producer-owned rewrite is **at** `Location` —
  `testing:audit`'s adopter row says exactly that of its own rules — so claiming off-site to reach
  the disposition asserts something false about where the fix goes, the same defect as retargeting
  `Location`.
- **Off-site's disposition is also the wrong destination.** It routes to surface-only, which is right
  when nothing in the session can apply the fix and a loss when the producer ships a surface that
  can. Reaching it would trade a misapply for a non-apply, not close the gap.
- **`Auto-applicable: No` has no path to the route that actually misapplies these rows.** Step 4's
  surface-instead-of-auto-applying fence sits under its **correctness-class** heading. A prose-style
  row classifies as cleanup by content, and the cleanup route hands that class wholesale to
  `/simplify`, which — Step 4's own words — "rediscovers cleanups from the working-tree diff — it
  does NOT read the findings files". A cell no consumer reads on that path cannot restrain it. That is the
  mechanical half of the gap: the crosswalk can already say a rule is not auto-applicable and still
  not stop the apply.

**Producer obligation — one declaration, in the crosswalk row.** A rule whose remediation is
contained to `Location` but owned by the producer's own remediation surface **leads its
`Auto-applicable` cell with** `No, remediated by <invocation>`, before whatever reason it goes on to
give. `<invocation>` is the skill and action a session can actually run — `/ai-slop:audit fix` —
never a reference-doc path, because a document is not something a relay can invoke.

**The declaration is per RULE and lives nowhere else, which is this contract's own settle-once rule
applied rather than restated.** "Auto-applicability is settled per rule, at contract time" (below)
says a rule's remediation shape does not vary run to run, so a per-finding decision is the same
decision taken repeatedly with less evidence. Who owns the repair is exactly such a fact. Requiring
every emitted row to carry a copy of it would be the per-finding restatement that section forbids,
and it would make conformance a property of a producer's emitter rather than of its rule set.

**How the consumer reads it: through the rule id every row already carries.** Every emitted row leads
its `Finding` cell with the qualified rule id ("Rule ids and thresholds" above), and this crosswalk
is the cross-producer registry that id resolves against by exact match — the same resolution the
Enforceability table's tier check is built on. A consumer holding a row therefore holds the route to
its declaration without a new column, a new field, or a second copy of a rule-level fact.

**A producer MAY also lead its `Action` cell with** `Remediate with <invocation>`, and a consumer MAY
route on that alone. This is a self-describing convenience for a consumer that cannot resolve the
contract, never a second declaration: where the two disagree, **the crosswalk row wins** and the row
is the defect. `ai-slop:audit` writes a near form of it today (`Guarded rewrite via /ai-slop:audit
fix`) on the rules whose `Action` has nothing more specific to say.

**Consumer disposition.** `fix-pass-mode.md` "Step 2" routes such a row to the named surface instead
of `/simplify` or the generic fixer, and "Step 4" invokes that surface only when it is **already
available in the session**. An unavailable, unrecognized, or malformed invocation is **surfaced —
never resolved, installed, or applied directly.** Applying it directly is exactly what the
declaration exists to prevent: the consumer would perform the edit without the discipline that makes
it safe, which is the misapply this section was written for wearing a different label.

**When the contract cannot be resolved, nothing here fires and the row takes the consumer's ordinary
classification.** That is the status quo rather than a fail-safe worth advertising, and the honest
place to say so is here. What bounds it in practice is not a rule but a habit both current adopters
already have: "Three emitters, one statement of each mechanic" below names fetching this contract at
run time and refusing to write when unreachable as the demonstrated conforming form, and both
adopters that persist do exactly that. So a findings file that exists is usually evidence the
contract was reachable at least once — usually, not always, and no consumer may assume it.

**No column, for the reasons the off-site column was rejected, plus one.** All three arguments above
carry unchanged — a shape every producer writes and every consumer parses, changed for a minority of
rows, to reach a verdict a leading token already reaches. What is new is that this table's own gate,
[`check-detector-findings-crosswalk.sh`](../../../scripts/check-detector-findings-crosswalk.sh),
locates the crosswalk by its exact **five-column** header and fails any row splitting into a
different field count, so a sixth column is a gate rewrite before it is a contract change.

**Declared dispositions, and a row declares at most one:**

| Remediation | How the row declares it | Consumer route |
|---|---|---|
| At `Location`, mechanical and meaning-preserving | `Auto-applicable: Yes — <argument>` | Auto-applied under Step 4's fence |
| At `Location`, owned by the producer's own surface | `Auto-applicable: No, remediated by <invocation>`, resolved through the row's rule id | Routed to that surface; surfaced when it is unavailable |
| Outside `Location`'s file | The off-site rule above; `Action` names the target file | Surface-only (Step 2) |

A row declaring **none** of them is not in breach — it takes the consumer's own classification, which
is where every row sat before this section existed. `testing:audit`'s rows are the live instance:
their repair is at `Location`, no skill owns it, and Step 4's judgment fence surfaces them. This
section adds a way for a producer to say who owns a repair; it does not make the relay omniscient
about repairs nobody claims.

## Auto-applicability is settled per rule, at contract time

`fix-pass-mode.md` "Step 4" owns the criterion — a fix is auto-applied only when it is contained to
its `Location`, high-confidence, and not a call for architectural judgment. What this contract owns
is the consequence for a detector author: **settle it once per rule in the crosswalk, not per finding
at apply time.** A rule's remediation shape does not vary run to run, so a per-finding decision is
the same decision taken repeatedly with less evidence.

Three rule shapes are never auto-applicable, and saying so is the contract's intent rather than a
limitation to route around:

- **Cross-file remediation** — not contained, by construction (above).
- **Architectural judgment** — the finding is an argument about where a boundary belongs, and the fix
  is a design decision. Layering, abstraction, and coupling detectors are the clearest case: they are
  **designed to inform a human.** Reaching the relay is still the whole point, because it is what
  gets their findings ranked, merged, and reported beside everything else; being surfaced rather than
  applied is the correct end of that route, not a failure of it.
- **Producer-owned remediation** — contained to `Location`, but safe only under discipline the
  producer owns (previous section). Not auto-applicable *by the consumer*; the point of the
  declaration is that it is applicable by the producer's own surface, which is the one route this
  shape does not reduce to surface-only.

**The cell's grammar carries the disposition.** `Auto-applicable` is read by a consumer, not only by
a human, so the cell leads with one of four forms and argues after it: `Yes — <argument>`,
`No — <reason>`, `No, remediated by <invocation> — <reason>` (previous section), or
`Not applicable — no row`. A reason that names an owner only in passing prose is not a declaration;
the lead is.

**Never shape a rule to look auto-applicable.** Narrowing `Location` to one file the finding does not
actually describe, or lowering `Confidence` to trip the escape clause, each defeats the criterion it
appears to satisfy — and the second buries a real finding beneath one nobody reported, per
`Confidence` above.

## A candidate that is not a finding

A detector examines more than it reports, and the examined-but-not-reportable outcome needs a home or
it settles into free prose nothing can read. Three outcomes, three homes; conflating them is the
failure to avoid:

| Outcome | Determined by | Home |
|---|---|---|
| The rule examined a candidate and its own stated evidence shows there is nothing to fix | the producer, per run | a **declined-candidate count** in `## Surfaces` |
| A real finding an operator has judged and decided to keep | the operator | [`finding-suppression`](../finding-suppression/README.md) |
| Not-a-defect claimed without the rule's stated evidence | nothing — the claim is unsupported | **a row**, under the rule the crosswalk names for that case |

- **A declined candidate is coverage, not a suppression.** Suppression is operator-authored,
  consent-gated, and keyed by a `finding_id` the consumer derives from `check`, `claim`, and `sites`.
  A producer writing an entry there unprompted would launder that consent gate and record an
  acceptance nobody made. **A producer proposes an entry and shows it to a human; it never writes
  one** — and a rule whose only remediation is a proposed suppression emits no row either, because
  handing it to the relay launders the same gate.
- **Where the count goes.** The returned-no-result limb of `## Surfaces`, in that section's existing
  line form, as a **count per rule id** — never a per-item rationale. The per-item argument belongs
  in the producer's human-facing report: a findings file carries the artifact, not the argument for
  it, which is the same rule that keeps a reviewer's reasoning out of a `Finding` cell. Counts also
  keep the section short enough to stay one line per surface, and are the form a trend across runs
  can be read from at all.
- **No evidence, no decline.** A rule that may decline states in its crosswalk row what evidence a
  decline requires. A candidate declined without that evidence is not declined — it emits.
- **No new field, and that is the decision.** A column or section for dispositions would push a
  per-run judgment into the shape the fix action parses, where every consumer would have to learn to
  ignore it; a separate file type would be structure with no reader. The disposition belongs to the
  **rule**, so it is declared once in the crosswalk and only its count is per run.

## Coexisting with other producers

Producers share one directory and the consumer merges across all of them —
[`fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) "Step 1: Build
the merge set" owns how. Three obligations fall on a producer:

- **Write your own file. Never append into another producer's.** Appending would need a
  write-ordering and locking convention that does not exist, and a partial write corrupts a file
  another producer owns.
- **Name yourself in `Surface(s)`.** Rows that match exactly are collapsed into one naming every
  contributor; that collapse is only legible if each producer identified itself.
- **Expect near-duplicate rows to survive.** Cross-producer matching is deliberately narrow, so do
  not pre-deduplicate against another producer's output — you would be guessing at a defect you did
  not detect.

## Emitting more than once

An apply marks the files it consumed and the consumer subtracts them —
[`fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) "Step 5" owns
the ledger. What binds a producer is one rule: **a detector re-runs and writes what it currently
finds; it never replays.** Re-emitting a stale file re-injects findings that may already be fixed.
How the ledger identifies what an apply consumed is "Step 5"'s to own and may change there; a
producer owes the rule regardless and never leans on the ledger to catch a replay.

## What a minimally conforming producer may omit

The admission test is stated by
[`fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) "Step 1" — meet
it and you are consumed. Beyond it, the coverage fields (`tier:`, `## By dimension`, `## Unparsed`,
`## Surfaces`) are required of `review:fanout`'s own writer to keep its report honest; a detector
with no analogue may omit them. **Omit rather than fabricate** — an invented `## Surfaces` line
asserts coverage that was never attempted, which is the failure that field exists to prevent. `date:`
is expected of every producer: it is the only record of when the detector actually ran, and a
consumer weighing findings against a moving tree needs it.

## Liveness

A detector that persists findings still owes the
[liveness-assertion contract](../liveness-assertion/README.md) "Core contract": fail loud, or publish
to an agent-readable channel. Writing a conforming findings file satisfies the second limb —
the file *is* the agent-readable channel, and the `fix` action is the agent that reads it. A detector
that writes nothing, reports green, and had findings satisfies neither.

## Three emitters, one statement of each mechanic

Emitting a conforming file means resolving the findings home through its whole rung order, computing
the branch sub-path, running the self-ignore guard, relativizing paths, escaping cells, and
formatting a colon-free UTC timestamp. `review:fanout` does it, `mutation-testing:audit` does it, and
the next detector will be the third. The decision recorded here is **why that is not three copies of
one thing**, and what would make it become one.

**The shared-source registry cannot hold this, mechanically.**
[`scripts/check-cross-plugin-source-drift.sh`](../../../scripts/check-cross-plugin-source-drift.sh)
clusters files by path-within-plugin across `plugins/*/` and compares hashes. Two consequences follow
and neither is a preference:

- A convention under `docs/` can never be a cluster — it is outside the tree the script walks.
- Registering a path that is not a live byte-identical cluster in two or more plugins **breaks** the
  check rather than recording a decision: it reports `REGISTRY STALE` and exits 1. Verified by adding
  one such line and running `--check`.

And there is no emitter **code** to share. Both existing emitters are prose a model executes, each in
its own plugin's context file. A byte-identity check has no subject.

**What prevents drift is that each mechanic has exactly one owner, reached by pointer:**

| Mechanic | Owner |
|---|---|
| Table shape and cell escaping | `default-mode.md` "Findings-file shape" |
| Path relativization and the colon-free timestamp | `default-mode.md` "Findings-writer contract" |
| Findings home, rung order, branch sub-path, slug rule, self-ignore guard | [`topic-docs.md`](../../../plugins/review/reference/topic-docs.md) |
| Which of those a non-fanout producer owes, and the fields it computes | this doc |
| A rule's threshold, tier argument, disposition, and auto-applicability | this doc's crosswalk |

A third producer adds a third *reader* of those owners, not a third statement of them. The failure
mode to guard against is a producer restating a mechanic locally, and the conforming form is already
demonstrated: `mutation-testing:audit`'s persist reference fetches this contract at run time and
refuses to write when it cannot reach it.

**How drift is caught, stated honestly: nothing mechanical, yet.** The conformance gate this contract
defers in Enforceability is what closes it, and a gate reading *emitted files* checks every producer
at once — a property a byte-identity check over source copies would never have had.

**Revisit trigger, and it fires itself — within a stated limit.** The first time a producer ships
emitter code as a file under `plugins/<x>/` and a second plugin carries a **byte-identical** copy at
the same path-within-plugin, `check-cross-plugin-source-drift.sh` reports that cluster as
`UNREGISTERED` until a decision is recorded, so the decision arrives at the gate rather than needing
to be remembered. The limit is in that word: a second copy that was **edited before it ever landed**
is not byte-identical, so it clusters as `DIFFERS` and the trigger never fires. Duplication born
already-drifted is therefore outside what any part of this decision detects, and the answer to it is
review, not a script.

## Enforceability

Classified per `melodic-software/standards` `conventions/engineering/enforceability-tiers.md`:

| Judgment | Tier |
|---|---|
| A persisted file conforms to the findings-file shape | **Deterministic when built** — frontmatter keys and table columns are mechanically checkable. **Buildable now**: the first producer exists, so a gate has something to run against. Still unbuilt. |
| `Confidence` is `high` or omitted, never `low` | **Deterministic when built** — a literal-value check. Folded into the same gate, and equally buildable now. |
| `Tier` is looked up from the rule rather than hand-picked | **Detect-then-judge** when built — narrowed by the crosswalk from where it stood. Every emitted row leads with a rule id, so a gate can check that the id has a crosswalk row and that the row's tier matches the row's own. What no gate can check is whether the run selected the RIGHT rule, which for a judgment-based classifier is not a machine question at all — the fail-safe-toward-emitting criterion is what bounds it instead of a check. |
| Every crosswalk row argues its disposition from a stated test | **Detect-then-judge**, and **BUILT**: [`scripts/check-detector-findings-crosswalk.sh`](../../../scripts/check-detector-findings-crosswalk.sh) `--check` runs in CI, failing an empty or prose-free test cell, an unqualified or duplicated rule id, and a row whose cells an unescaped pipe has shifted. Whether an argument is *sound* stays judgment — that is what the admission test carries, and no gate replaces it. |
| A row whose remediation is off-site is surfaced, not applied | **Detect-then-judge** when built — the consumption record names every surfaced row, so an off-site row appearing in the applied list is detectable; whether the fixer surfaced for the right reason is judgment. |
| An `Auto-applicable` cell uses one of the four leading forms | **Deterministic when built** — a literal-prefix read of a cell the crosswalk gate already parses, and the one that matters most is `No, remediated by <invocation>`, whose invocation must be a runnable `/plugin:skill` form rather than a doc path. A cell that names an owner only in trailing prose is the drift this catches. Unbuilt; it is one condition away in that gate. |
| A producer-owned row is routed to its named surface, not to `/simplify` | **Reasoning-only** — the consumption record states what the cleanup route changed, not which skill the fixer invoked, so nothing outside the session can tell a routed row from one `/simplify` silently declined to touch. This is the honest limit of the disposition: the declaration is checkable, the honoring is not. |
| A declined candidate is reported as a count rather than dropped | **Reasoning-only** — a count in `## Surfaces` is greppable, but nothing outside the producer knows what the run examined, so no gate can tell a declined candidate from one never generated. |
| A producer's coexistence behavior (own file, self-named surface) | **Detect-then-judge** when built — appending into another producer's file is detectable; whether a `Surface(s)` value identifies the producer usefully is judgment. |

**Mechanical enforcement is still deferred**, but no longer for want of a subject. Recorded with
event triggers rather than dates:

- **Recheck trigger (conformance gate) — FIRED.** `mutation-testing:audit` is the first detector to
  reach `main` with a persist path, so a gate now has a real emitter to check rather than a fixture.
  What that unblocks: the shape and `Confidence` judgments above are both a mechanical read of a file
  this repository can produce on demand. No gate is written here — naming the trigger as fired is
  what stops the deferral from reading as permanent.
- **Recheck trigger (this doc's depth) — MET.** The pilot ran, and both gaps it surfaced are closed
  here: a producer whose remediation site is not its `Location` now has a disposition, and an
  examined-but-not-reportable candidate now has a home. This doc is no longer a stub, and what
  remains deferred is mechanical enforcement, not depth.

## Adopters

An **adopter** is a producer outside `review:fanout` that conforms to this contract. A row asserts
that the producer conforms today — **tabled only once it actually does**, because tabling a planned
adopter asserts what a reader cannot rely on.

| Producer | Status | Notes |
|---|---|---|
| `mutation-testing:audit` | Conforming, opt-in | The first detector pilot. Persists surviving mutants behind `--persist-findings`; bare invocation still reports and stops. Maps each Phase 4 verdict class to one crosswalk rule and emits `Confidence: high` only. **Its rule selection is a fresh-context reviewer's judgment, not a computation** — so it is the worked case for the fail-safe-toward-emitting criterion rather than an exception to it. It has **two** withholding boundaries and both fall through to the emitting `unclassified` rule: an equivalence verdict that cannot cite its demonstration, and an aridity call whose proposed suppression entry does not bind a node kind from its enumerated vocabulary and name the behavior the suite deliberately leaves unasserted. A wavering judgment can therefore add a row but never silently remove one. **Both bars sit at classification rather than at persist time**, which is what makes the fall-through one answer per survivor instead of a report and a findings file that can disagree — and it means the bar binds a run that never persists, where an unevidenced withholding claim is read by a human rather than by the relay. Omits `tier:`, `## By dimension`, and `## Unparsed` as a detector with no analogue for them; keeps `## Surfaces`, which is the whole payload of a run that examined mutants and found nothing, and where its declined-candidate counts go. Its remediation is off-site — the covering test, not `Location` — so every row it emits names the target in `Action` and the consumer surfaces rather than applies. It declares no remediation owner and is unaffected by that disposition: its `Auto-applicable` cells keep the plain `No — <reason>` form, and off-site is decided first in any case. |

| `testing:audit` | Conforming, opt-in | The first static Tier 1 detector, and the contract's first fully mechanical rule set: selection is a deterministic token/structure scan with no execution and no withholding verdict, so the fail-safe-toward-emitting criterion is met by construction — the one uncertain case (a deliberate interaction-style test matching `rule-mock-only-oracle`) still emits, with `Confidence` omitted per the high-or-omitted rule. Persists behind `--persist-findings`; bare invocation reports and stops. Leads every `Finding` cell with the qualified rule id and the fired threshold in the run's own values; `Confidence` is `high` on the two deterministic-defect rules and omitted on `rule-mock-only-oracle`, never `low`. `Location` is repo-relative (computed through git's own prefix under a narrowed scan root) and IS the remediation site — the repair belongs in the flagged test — but every row is oracle-judgment repair, so none is auto-applicable. It declares **no** remediation owner, and that is correct rather than an omission: no skill owns choosing the assertion a behavior deserves, so its cells keep the plain `No — <reason>` form and Step 4's judgment fence surfaces the rows, exactly as before. Omits `tier:`, `## By dimension`, and `## Unparsed`; keeps `## Surfaces` with per-rule declined-candidate counts, stating honestly that the recomputed-expectation rule's candidate assertions are not tallied v1 rather than inventing a number. A deliberate case is declined at selection by an in-file `cant-fail-ok: <reason>` annotation — the rules' stated decline evidence, counted in `## Surfaces` — which is a recorded decision at the test site (the repo's incumbent test-gate annotation shape), not a suppression of an emitted finding, so the finding-suppression home is not in play. Its `--check` mode is the fail-closed gate the liveness contract's fail-loud limb asks of a gating form: findings exit 1; an unread input, a dead engine, or a scan that examined nothing exits 2 rather than passing. |

| `ai-slop:audit` | Conforming, default-on for repo-examining runs | The first prose detector, and the first with a rule-sourced tier spread (twelve SUGGESTION style rules, three IMPORTANT generation-residue rules — each argued in its crosswalk row). Selection is fully mechanical (byte-sequence, phrase-list, and density scans; no withholding verdict), so the fail-safe criterion is met by construction; its decline evidence is the in-file ignore markers, config path exemptions, and code-fence stripping, counted per rule in `## Surfaces` from the detector's own `Summary` rows. The findings file is model-persisted by the skill (the deterministic `detect.sh` emits a parseable report only), per its `context/persist-findings.md` read of this contract: fetch this contract before the first write and refuse to persist when unreachable. Leads every `Finding` cell with the qualified rule id and the fired condition in the run's own values (the zero-tolerance marker or the density/threshold/hits/words tuple); `Confidence` is `high` on every row. Judgment-rubric findings never enter the file — no crosswalk row, no relay. **The first producer to declare producer-owned remediation**, and the case that section was written from: only `rule-utm-params` is auto-applicable, and its other fourteen rows are contained to `Location` yet safe only under the rewrite discipline in this plugin's own `reference/rewrite-guide.md`. Each of those fourteen rows leads its `Auto-applicable` cell with `No, remediated by /ai-slop:audit fix`, which the relay resolves through the qualified rule id every emitted row already leads its `Finding` cell with — so those rows route to that action instead of the cleanup route's `/simplify`, which reads no findings file and loads no rewrite guide. **The declaration required no change to what this producer emits**, which is the point of siting it in the crosswalk: its emitted `Action` cells already describe the repair and already name the fix action on the rules with nothing more specific to say. After that fix runs the skill re-runs the detector and re-emits, so no stale file survives its own remediation. Omits `tier:`, `## By dimension`, and `## Unparsed`. |

`review:fanout` is not an adopter and is deliberately absent from the table: it is the **reference
writer** whose file format this contract points at, and it sits on the other side of the boundary
this doc draws.

## Versioning

This contract is versioned in [`CHANGELOG.md`](CHANGELOG.md). Changing a producer-owned field's rule,
the coexistence obligations, or an enforceability verdict is a major bump; additive guidance or a new
adopter row is a minor bump; docs-only clarification is a patch.

## External authority

- [`plugins/review/skills/fanout/context/default-mode.md`](../../../plugins/review/skills/fanout/context/default-mode.md) — the findings-file shape this contract points at and never copies.
- [`plugins/review/skills/fanout/context/fix-pass-mode.md`](../../../plugins/review/skills/fanout/context/fix-pass-mode.md) — the consumer algorithm, including merge-set construction and consumption marking.
- [`plugins/review/context/severity.md`](../../../plugins/review/context/severity.md) — the severity-tier and confidence vocabularies a producer emits, and the consumer-precedence rule that overrides the baseline.
- [`plugins/review/skills/fanout/context/findings-normalization.md`](../../../plugins/review/skills/fanout/context/findings-normalization.md) — the rank order that makes `low` worse than omission.
- [`plugins/review/reference/topic-docs.md`](../../../plugins/review/reference/topic-docs.md) — the findings-location binding `review:fanout` resolves through, carrying the rung order, branch sub-path, slug rule, and guard a producer therefore never restates.
- [`docs/conventions/topic-docs/`](../topic-docs/README.md) — the tier semantics, guards, and invalid-root rule that resolver implements; not itself the pointer for where a producer writes.
- [`docs/conventions/finding-suppression/`](../finding-suppression/README.md) — the operator-authored suppression record whose `check:` constituent a qualified rule id is, and the consent gate a producer proposes into rather than writes.
- [`REVIEW.md`](../../../REVIEW.md) — this repository's own project severity vocabulary, the live instance of the consumer-precedence override a producer maps to.
- [`scripts/check-cross-plugin-source-drift.sh`](../../../scripts/check-cross-plugin-source-drift.sh) — the shared-source cluster mechanism the emitter decision is measured against, and the gate its revisit trigger fires at.
- `melodic-software/standards` `conventions/engineering/enforceability-tiers.md` — tier vocabulary and routing rule.
- [`liveness-assertion`](../liveness-assertion/README.md) — the fail-loud-or-agent-readable contract a detector satisfies by persisting.
- [`PLUGIN-PHILOSOPHY` Convention registry](../../PLUGIN-PHILOSOPHY.md#convention-registry) — one owner doc per shared concern, and the before-a-second-adopter deadline this stub answers.
