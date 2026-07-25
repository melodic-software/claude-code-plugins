# Decision record — independent per-question agents

Six open decisions were each assigned to a dedicated subagent, deliberately blind to the
orchestrator's own recommendations (`verify/reconciliation.md` and PLAN.md's pending-amendments
section were withheld). This file is the single consolidated view; per-decision reasoning lives in
the sibling `D<n>.md` artifacts and is not copied here.

**Status: recommendations, not ratified decisions.** Nothing here is applied to the ledger or the
Brief. D8 (challenge of the 57 INLINE-ONLY rows) was still running when this was written.

## Results

| # | Question | Independent verdict | vs. the orchestrator's recommendation |
|---|---|---|---|
| D1 | Is nested spawning optional or a hard prerequisite? | **Neither.** Split the concept: *throughput* nesting stays optional; *independence* nesting is replaced by an orchestrator-mediated verification hand-off. | Rejected both offered options — the binary encoded a category error |
| D2 | Does dispatch satisfy producer ≠ critic? | **Yes, for both skills.** Overturn the `quality-gate` NO. | Kept the answer, moved the limit to the right skill |
| D3 | Does a start-of-run question block dispatch? | **No — pre-dispatch parent work.** Replace the positional "mid-flow" wording with an information-dependency test. | Same answer, better test; diagnosed why batches split |
| D5 | How does the discipline reach the agent? | **Preload the existing skill.** Author nothing new. | Collapsed a distinction that did not exist |
| D6 | Retire `research-deep` and `explore-deep`? | **Split. Keep `research-deep`. Retire `explore-deep` conditionally.** | Overturned; orchestrator's reading judged motivated |
| D7 | Whole-skill or phase-level dispatch? | **Phase-level**, whole-skill verdict becomes a roll-up. | Same answer, went further on the outcome gate |

## The convergent finding

D1, D2, and D7 arrived independently at the same structural rule without seeing each other:

> **The orchestrator owns independence. A dispatched agent never verifies its own work.**

- D1: *"independence is a property of context provenance, not of spawn parentage"* — a verifier that
  reads the artifact off disk has never seen the producing context, whoever spawned it. So a skill
  that cannot spawn its verifier emits a verification request and the orchestrator dispatches a
  **sibling**.
- D2: *hoisting, not nesting* — the parent makes one dispatch hop; the inner dispatch the skill
  mandates is satisfied at the outer boundary and dissolves.
- D7: the outcome gate splits three ways rather than travelling whole with the producer.

This extends D4's proposed principle (the parent owns the pre-dispatch envelope) to also cover the
**post**-dispatch boundary. D4 should be restated to include it before it is put up for ratification.

## Detail worth carrying forward

**D1 — the distinction that resolves it.** Classify every nested spawn by what the nesting buys.
*Throughput*: N independent units, identical epistemic standing; absent nesting the parent does them
sequentially — genuinely slower, same coverage. *Independence*: a context that has not seen what the
parent produced; absent nesting the parent self-critiques — not slower, **weaker**. Decision 3's
degradation clause is true for the first class and false for the second. Existing marketplace
practice already models the remedy: `docs-hygiene:compress` dispatches separate compress and audit
subagents from the main session precisely because *"subagents cannot reliably spawn the verifier
themselves."*

**D2 — two guarantees, not one.** *Independence* (producer ≠ critic) is a property of who renders the
verdict; dispatch buys it. *Decorrelation* (distinct lenses) is a property of how many priors examine
it; dispatch does not buy it and never claimed to. `review:quality-gate` states *"Depth, not breadth.
This skill picks ONE lens per invocation"* and routes breadth to `fanout` — so dispatching it forfeits
no lens. Dispatch also adds no new correlation: main(Opus) → sub(Opus) → reviewer(Opus) is exactly as
correlated as main → reviewer. The decorrelation remedy both skills already name is a cross-vendor
reviewer, which is orthogonal to this decision. The NO belongs on `fanout`, not `quality-gate`.

**D3 — the three-cell discriminator.** *Parameter* question: answerable from intent, arguments, and
the conversation before the run starts — never a blocker; test is *could the parent ask this without
having read a single file the skill reads?* *Discovered* question: its existence or content depends on
what the run finds — blocks only if it steers. *Elicitation* question: blocks when the answer IS the
deliverable. The batches split because "mid-flow" was read positionally (inside the step list) rather
than temporally.

**D5 — the split already exists.** `discovery:research`'s SKILL.md is already the thin mandate layer
(the bars, phase structure, outcome gate) and `context/discipline.md` is already the heavy sibling
(tier tables, recipes, calibration). "Preload a thin contract, keep heavy reference in siblings"
describes the current file tree. The only real question was whether the mandate arrives *guaranteed*
or *on request* — guaranteed, because the skill exists to stop an agent doing less than the bars
require, and `discipline.md` says so in its own words: *"Models satisfice to stated numbers."*

**D6 — why the retirement reading was motivated.** `MIGRATION-PLAYBOOK.md:129-136` has an operative
rule, a classification, and a subordinate mechanism observation. The retirement argument treated the
mechanism observation as the whole justification. The passage states its own test in its closing
sentence: **same execution path vs. a second execution path** — not frontmatter vs. runtime. A runtime
`Agent()` call changes which mechanism creates the second path; it does not collapse two paths into
one. Separately, the observation remains literally true for `research-deep`: Tier 1 needs `Workflow`
and the multi-topic path needs `Agent`, which errors even inside a true fork. And `plugins/discovery/agents/`
does not exist yet, so retiring `explore-deep` today would delete real behavior (project-memory
loading, sidecar-on-collision) in favor of something unbuilt.

**D7 — the outcome gate splits three ways**, rather than travelling whole with the producer:

- Criteria 1–6 (mechanical) — dispatch with the producing span, as a loop-exit condition emitting a receipt.
- Criterion 7 (every claim HIGH confidence) — a parent-dispatched **sibling verifier** reading the sidecars against the claims.
- Criterion 8 (project fit) — **parent, inline**; it needs the consuming project's convention files and the live task, neither of which the researcher was pointed at.

## Verdict changes proposed (none applied)

- `review:quality-gate` — INLINE-ONLY → dispatchable (D2).
- `discovery:blindspot` — INLINE-ONLY → DISPATCH-OPTIONAL (D3; independently corroborated by
  validator-B and the renorm pass).
- `bug-report:write` — INLINE-ONLY confirmed, justification replaced (D3).
- `planning:draft-goal-condition` — DISPATCH-OPTIONAL confirmed (D3).
- `claude-config:audit-instructions`, `docs-hygiene:audit-derivability` — dispatchable without the
  nesting env var, under D1's hand-off model.
- `explore-deep` — retire, conditional on `discovery:explorer` covering project-memory loading and
  sidecar-on-collision. `research-deep` — keep (D6).

## D8 — challenge of the 57 INLINE-ONLY rows under the inverted default

Ran under the user's inverted burden of proof: dispatch is the default, INLINE-ONLY is the claim
needing justification. Full detail in [`D8-inline-challenge.md`](D8-inline-challenge.md).

**One root cause, not fourteen separate misjudgements:**

> **Multi-action skills were graded on their heaviest action.** The verdict was set by the mutating or
> interactive action, while a read-only sibling action in the *same skill* — `audit`, `scan`,
> `dry-run`, `status`, `check`, `fetch` — carries no blocker at all and is where nearly all the
> context volume actually lands.

Eleven of fourteen challenges are instances, and in seven cases the skill's own text says the
read-only action is unblocked *in words* that the batch rationale never engaged: `docs-hygiene:compress`
("Audit is read-only — no dispatch"), `repo-hygiene:clean` ("read-only inventory… Risk: Safe"),
`code-tidying:tidy` ("Do NOT make edits. Do NOT branch. Do NOT push"), `github:advise` ("A bare
invocation performs zero mutations"), and three more.

This is the same defect D7 identified from the other direction. Phase/action granularity is not a
refinement — the whole-skill verdict actively produced wrong answers on 14 rows.

**Coverage, stated honestly and tiered** — the agent was told about the earlier C1 coverage overstatement
and deliberately did not repeat its shape. Counts verified by script:

| Tier | Count |
|---|---|
| Opened the SKILL.md, full read | 19 |
| Opened the SKILL.md, targeted read | 6 |
| **Not opened — judged on batch rationale only, inherited not verified** | **32** |

14 challenged (all from the 25 opened), 11 upheld after its own read, 32 upheld without independent
verification.

**It then measured the risk in the 32 it did not open**, rather than leaving it as a caveat: it applied
its own root-cause predictor by script — grep each unopened skill for a read-only action-router entry.
Three hits across all 32, and all three are benign (`claude-memory:stateless` `status` is already served
by an `!`-precomputed snapshot, so there is nothing to reclaim). A second ranking by read-only phrase
density surfaced `session-flow:reconcile`; it opened that one too and cleared it.

**Challenges split by dependency:** 11 stand alone and need no pending decision (Group A); 3 depend on
D3's start-of-run rule or the parent-supplied-scope principle (Group B).

It also corrected the checklist **in the opposite direction** — `event-storming:methodology` is
over-carved — and found a same-plugin split the normalization pass missed *inside a single batch*.

## Method note

Six for six, every agent overturned or improved the orchestrator's recommendation — and in five of six
the defect was the *framing* rather than the facts: a misapplied limit (D2), a positional/temporal
ambiguity (D3), a false binary (D1), a distinction that did not exist (D5), and a forced pairing of two
non-symmetric skills (D6). That is the argument for per-question independent agents: they are not
finding different evidence, they are catching where the question was posed wrongly.
