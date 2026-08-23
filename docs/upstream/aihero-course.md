# Upstream source: AI Hero course lessons (Matt Pocock)

Provenance record for everything in this marketplace vetted against the AI Hero **crash course**
lessons (Matt Pocock's course on working with coding agents): the original six lessons (handoff,
phase boundaries, compaction, auto-compaction, plan mode, grilling) plus the course's nine
**Steering**-section lessons. This is a distinct source from the
[mattpocock/skills](https://github.com/mattpocock/skills) repository, whose record is the SSOT at
[mattpocock-skills.md](mattpocock-skills.md): the course is prose lessons with no releases, tags,
or changelogs, so it needs its own recheck regime. Where a lesson restates something the skills
repo also ships, the row cites both bases. The course's **Shipping** section (11 lessons) is a
separate absorption effort with its own record,
[aihero-shipping-course.md](aihero-shipping-course.md) — one convention, two scoped records.

Vetting ran as six lanes on the `pocock-course-lanes` contract
(issues [#2899](https://github.com/melodic-software/claude-code-plugins/issues/2899) through
[#2904](https://github.com/melodic-software/claude-code-plugins/issues/2904)), extended by three
steering lanes ([#2909](https://github.com/melodic-software/claude-code-plugins/issues/2909),
[#2910](https://github.com/melodic-software/claude-code-plugins/issues/2910),
[#2911](https://github.com/melodic-software/claude-code-plugins/issues/2911)). Lanes decide but
never implement: every plain ADOPT row points at a filed work item (the ADOPT terms sub-form,
defined with the row schema below, executes via the lane 6 term-verdict table instead); changes
execute through the normal pipeline.

**Record provenance and supersession.** Lanes 3–5 were each closed by two parallel session
chains — one writing rows into this document's copy on the contract branch
`claude/plan-mode-discussion-55kszx`, one writing the interim record `aihero-core-lanes.md` on
the chain branch that merged this document. This consolidated copy reconciles both (verdicts
were convergent; deltas are annotated per lane, and the union of filed items stands) and is the
AUTHORITATIVE record from its merge onward. The contract branch's own copy of this file is
SUPERSEDED — in particular its lane 5 section predates the audit pass that filed
[#2998](https://github.com/melodic-software/claude-code-plugins/issues/2998) — and that
branch's eventual merge must take the mainline copy of `docs/upstream/aihero-course.md`, never
its own. The contract PLAN.md's Goal/acceptance still say "six lanes"; extending its lane index
with lanes 7–9 and the steering-widened coverage scope is a PENDING amendment owed when that
branch merges. The `teach`-skill comparison coordinated on
[#2904](https://github.com/melodic-software/claude-code-plugins/issues/2904) already folded its
outcome into the SSOT (merged PR #2958; `teach` row corrected to Derived) — no second
convention emerged.

## Row schema (fixed at creation, per amendment A2)

Each row is a four-part record per
[docs/conventions/upstream-drift/README.md](../conventions/upstream-drift/README.md): the claim,
the basis it was derived against, the as-of date, and a recheck trigger. Columns:

| Lesson claim | Ours | Verdict | Reasoning, basis, as-of |

Verdicts: **ADOPT** (with the filed work item), **REJECT** (with reason), **TRACK** (on a named
event), **COVERED** (already present at parity or stronger, with evidence). One sub-form:
**ADOPT terms** marks a vocabulary adoption whose execution path is the term-verdict table
(lane 6) rather than a filed work item.

**Recheck trigger, all rows (fixed at creation):** divergence at re-fetch. A read-time re-fetch
of the row's basis (the lesson text, or the upstream artifact the row cites) finds the source no
longer matching the record; the divergence, never the lookup, fires the row, and a firing follows
the upstream-drift maintenance procedure. A row may state a stronger trigger inline; bare "when
the lesson updates" is not a valid trigger form here because the course publishes no observable
update signal.

**Re-fetch basis for course-lesson claims (deliberate, maintainer-decided):** the lesson pastes
are NOT durably committed — course pages are account-gated, and the maintainer authorized
committing the verbatim texts only on the contract branch's topic slice, pruned before any
merge to this public default branch. A future re-fetch therefore compares against the live
course (account required) or, as the durable proxy, the companion skills repo pinned per the
SSOT — the same regime the sibling
[aihero-shipping-course.md](aihero-shipping-course.md) records. Where a row's basis names a
lesson file under `docs/topics/pocock-course-lanes/lessons/`, that citation is provenance (what
the lane graded, with its as-of date), not a promise the file exists on this branch.

## Lane 1: handoff (issue #2899, decided 2026-08-17)

Basis for all lane 1 rows: the course handoff lesson as captured in the lane contract
(`docs/topics/pocock-course-lanes/PLAN.md`, 2026-08-17) plus upstream
`skills/productivity/handoff/SKILL.md` read live at `068b6e0` (2026-08-17). Our side read live
the same day: `plugins/session-flow/skills/handoff/SKILL.md`,
`plugins/session-flow/reference/save-point.md`, `plugins/session-flow/reference/structure.md`
(exploration verified by a fresh-context agent, 14/14 sampled claims confirmed).

| Lesson claim | Ours | Verdict | Reasoning, basis, as-of |
|---|---|---|---|
| Handoff serves crossing boundaries: another agent, another repo, a colleague, a forked side task | `session-flow:handoff` "When to invoke" list; "sharing state with another session or machine" bullet | **ADOPT** (as a union) | User decision (#2899 comment 1): our dominant session-chain use (dumb-zone escape, session-ID chain, retrospective reconstruction) is named first-class ALONGSIDE his taxonomy, not instead of it; the deliverable is explicit routing signals for which form to use when. Filed: [#2956](https://github.com/melodic-software/claude-code-plugins/issues/2956). As-of 2026-08-17 |
| A single purpose argument ("What will the next session be used for?") tailors the doc to the next session's focus | No purpose argument; surface is `[file\|prompt] [topic]`; intent lives in the verbatim Original goal section | **ADOPT** | Shape decided in-lane: optional trailing free text `[file\|prompt] [topic] [purpose...]`; tailors emphasis only (Resumption brief lead, Suggested skills selection, Remaining-actions order); never drops sections; never alters the resume-prompt shape (find-handoff detection contract); Original-goal immutability wins on conflict. Filed: [#2955](https://github.com/melodic-software/claude-code-plugins/issues/2955). As-of 2026-08-17 |
| Save the handoff to the OS temp directory, not the current workspace | `<memory_dir>/handoffs/` (default `.work/handoffs/`), memory tier, self-gitignored | **REJECT** | Placement is load-bearing for us: retro's `previous_handoff` chain-walk, find-handoff recovery, and the cross-machine origin line all depend on workspace placement; OS-temp volatility is the failure class upstream's own corpus hit (temp-sweep in mattpocock/skills#306 context, durability ask in #482). His self-cleaning benefit is replaced by user-controlled removal. Confirms the #1477 finding-4 verdict (PR #1560). As-of 2026-08-17 |
| Lifecycle: temp placement self-cleans, so files never accumulate | Accumulation by design ("Multiple handoffs accumulate in the directory, fine", structure.md); nothing expires files | **REJECT** (silent expiry) | User decision (#2899 comment 1): handoffs stay primarily ephemeral in a location we control; cleanup is user-controlled removal, never silent expiry or OS cleanup. Retention is load-bearing (chain-walk, recovery, carry-forward), which is the recorded #1477 finding-4 rationale (issue comment 5084364831); this lane confirms rather than reverses it. Promote-content-never-file rule and worktree caveat filed: [#2956](https://github.com/melodic-software/claude-code-plugins/issues/2956). As-of 2026-08-17 |
| Do not duplicate content captured in other artifacts (specs, plans, ADRs, issues, commits, diffs); reference by path or URL | Partial: "Summarize; never transcribe" (File roles), "reference it rather than restating" (Decisions); no general rule | **ADOPT** | User decision (#2899 comment 1): state the general rule explicitly in the skill body, mirroring upstream's wording; explicit over implicit. Filed: [#2956](https://github.com/melodic-software/claude-code-plugins/issues/2956). As-of 2026-08-17 |
| Include a suggested-skills section naming what the next agent should invoke | Suggested skills is a mandatory section of the handoff structure | **COVERED** | Present at parity or stronger (presence-gated per-skill suggestions, structure.md mandatory section set). As-of 2026-08-17 |
| Redact sensitive information (API keys, passwords, PII) | Mandatory redaction step with the git-remote-userinfo strip exception | **COVERED** | Ours is the more specified form of the same rule. As-of 2026-08-17 |
| `disable-model-invocation: true`: only the user triggers a handoff | Model-invocable under strict trigger discipline (instrument signal, observed drift, user report; never self-estimated budget) | **REJECT** | User decision (round 5): proactive "we should hand off now" prompting is wanted, and instrument-triggered forks plus skill-to-skill reach (his own invocation-reach invariant makes user-only skills unreachable from other skills) depend on model invocation. Token cost of carrying triggers acknowledged and accepted. Known gap: the zone instrument is statusline-teed and silent in cloud/headless sessions, filed as [#2957](https://github.com/melodic-software/claude-code-plugins/issues/2957). As-of 2026-08-17 |
| A handoff skill needs only ~15 lines | Three-layer engine (skill, shared save-point engine, structure doc) | **REJECT** | The engine's size is accumulated incident response, not up-front design: claim provenance and constraint re-scan from his own failure corpus (#1477, PR #1560), loop re-arm (#1447/#1515), rooted resume paths (#1780), Original-goal immutability (#1906), background-continuation disambiguation (#2115). Our minimal tier already exists as prompt-only mode (writes no file, documented retro-gap cost). As-of 2026-08-17 |

House decisions recorded alongside the rows (not lesson claims): the worktree caveat (a handoff
written inside a worktree dies with `git worktree remove`; acceptable only when the worktree
completes as a merged PR unit) and the promote-content-never-file rule (durable value is promoted
into committed artifacts; no handoff file is ever committed). Both in
[#2956](https://github.com/melodic-software/claude-code-plugins/issues/2956).

## Lane 2: phase boundaries (issue #2900, decided 2026-08-17)

Basis for all lane 2 rows: the course lesson "Clear, Compact, Handoff, Or Subagent" (verbatim
paste, 2026-08-17, session cache). Our side read live the same day:
`plugins/session-flow/skills/workflow/context/continuation.md`, the workflow SKILL.md, the
sibling continuation skills, and `plugins/context-guard/reference/reader-contract.md`
(exploration verified by a fresh-context agent, 23/23 sampled claims confirmed). The repo-side
tree (`PHASE-BOUNDARIES.md`) was previously audited in the SSOT (ask-matt row,
[mattpocock-skills.md](mattpocock-skills.md)); rows below cite that audit where the course
restates it.

| Lesson claim | Ours | Verdict | Reasoning, basis, as-of |
|---|---|---|---|
| The five-option decision belongs at the phase boundary only; work the questions in order; they are subjective judgment calls | Router runs "at a phase boundary"; compact edge is boundary-only; "ask in order, first yes wins"; mid-stage with a healthy window the step is skipped; judgment tests govern degraded or unknown zones | **COVERED** | Parity: boundary-only trigger, ordered first-yes-wins discipline, and the judgment-call framing were all recorded at parity in the prior repo-tree audit; the course version adds nothing new here. As-of 2026-08-17 |
| Five options: continue, clear, compact, handoff, subagent | Derived outcome set of six terminals (continue, `/clear`, `session-flow:handoff`, `session-flow:continue-in-background`, `session-flow:clean-stop`, `/compact`); subagent delegation is non-terminal via `session-flow:orchestrate` | **COVERED** (stronger) | Our outcome set is derived from installed mechanisms, adding clean-stop (machine going away) and user-gated background continuation his tree lacks; the subagent difference is decided in the AFK row below. As-of 2026-08-17 |
| Compact "compresses your context and seeds a new session with it" | No such claim anywhere in the family; fork-vs-compaction tradeoff owned by handoff | **REJECT** (as a harness claim) | Refuted harness claim: verdict C4 in the pocock-course-lanes contract (two-pool, 2026-08-17): compaction continues the SAME session over a structured summary; only fork or `--fork-session` makes a new session id. The lesson's operational advice (compact last, steer the summary) is unaffected and covered below. As-of 2026-08-17 |
| Continue first when the next phase needs this phase as a primary source; the implementation wants the grilling reasoning verbatim | Q2 prefers continue "when the next stage consumes this stage's reasoning verbatim; a summary of the reasoning is not the reasoning" | **COVERED** (previously ADOPTED) | The course version confirms the criterion already adopted from the repo tree in the v1.2 sync (PR #2082); ours zone-gates it (never overrides a degraded zone, where handoff remains the route). As-of 2026-08-17 |
| Numeric anchors: 30k tokens after grilling means continue; 80k with a small task fits; 150k means leave; smart zone budget ~150k | No inlined numbers; the router consumes only the context-guard zone word per its reader contract; band values live in the contract as declared judgment defaults | **REJECT** (as adopted numbers) | Claim-ladder bucket ii (amendment A1): his figures are recorded as folklore anchors with named provenance, never adopted as numbers; our baseline is instrumented zone readings plus context-guard's declared judgment-default bands. Confirms the repo-tree rejection of the ~150k figure without repeating its "measured bands" overclaim (lane-6 correction pending). As-of 2026-08-17 |
| Clear when the context is irrelevant and disposable; the cheapest move, takes zero time | Q3: `/clear`, "the cheapest reset, asked before any writing mechanism: capturing state nothing needs is pure cost" | **COVERED** | Parity; ours orders it after the hard-fact questions (machine going away, explicit background request) with each edge's ordering purpose stated. As-of 2026-08-17 |
| Handoff is narrow: only for passing to another agent, another directory or colleague, or forking a mid-phase side task | Q4 handoff covers state-must-survive as well as boundary crossing; the session-chain use is named first-class per lane 1 | **REJECT** (the narrowing) | Confirms both the lane-1 UNION decision (issue 2899) and the prior repo-tree rejection: the narrowing contradicts our fork-beats-compaction stance, where handoff replaces compaction in a deep window with nothing travelling at all. Routing-signals deliverable already filed: [#2956](https://github.com/melodic-software/claude-code-plugins/issues/2956). As-of 2026-08-17 |
| AFK criterion: if the task can run away-from-keyboard with no steering, spawn a subagent (a tree terminal) | Delegation is deliberately non-terminal, owned by `session-flow:orchestrate`; autonomous feasibility lives in Q1's feasibility half | **ADOPT** (modified) | Q20 decision (user-delegated to the session, 2026-08-17): adopt the AFK question as a router edge that points to orchestrate for the spawn-brief decision; delegation stays non-terminal so orchestrate keeps spawn ownership, and continue-in-background's explicit-intent launch gate is untouched because the router suggests and never launches. Filed: [#2971](https://github.com/melodic-software/claude-code-plugins/issues/2971). As-of 2026-08-17 |
| Compact is the default, not the first reach; it sits at the bottom; pass it a steering instruction | Q5 fallthrough: `/compact` "at a phase boundary only, with a steering hint naming what the summary must keep", ordered last deliberately | **COVERED** (stronger) | Parity or stronger: ours adds the least-intelligent-point warning and defers the full tradeoff to handoff's "Fork beats compaction when the window is deep". `/compact [instructions]` support is verdict C6, CONFIRMED docs-only single-pool. As-of 2026-08-17 |
| Every move except continue converts a primary source into a secondary source; pay the lossiness only when staying costs more | Q2's reasoning-verbatim criterion embodies the same trade; handoff owns the fork-vs-compact statement of it | **COVERED** | The concept is present without the dictionary vocabulary; adopting the terms (primary and secondary source, smart zone, AFK, phase boundary) is lane-6 territory ([#2904](https://github.com/melodic-software/claude-code-plugins/issues/2904)). As-of 2026-08-17 |

House decisions recorded alongside the rows (not lesson claims), all from the lane interview
(Q21-Q23, 2026-08-17): the Q9 router evolution consumes plan, work-item state, and session
history via presence-gated pointers to the existing informants (orient's read patterns,
reconcile's liveness answer, the workflow checklist, the work-item seam), never duplicated
reads; autonomy is two-tier (a per-invocation explicit `auto` opt-in at top level, mirroring
continue-in-background's explicit-words precedent and never a standing config, plus the
orchestrator relay codified as the autonomous tier for delegated work) with the I23
reconciliation stated in the build item; the router's missing eval coverage and the
context-guard reader-contract drift are filed as their own items. Filed:
[#2971](https://github.com/melodic-software/claude-code-plugins/issues/2971),
[#2972](https://github.com/melodic-software/claude-code-plugins/issues/2972),
[#2973](https://github.com/melodic-software/claude-code-plugins/issues/2973).

## Lane 3: compaction doctrine (issue #2901, decided 2026-08-17)

Basis: the merged Compaction and Auto-Compaction lessons (source:
`docs/topics/pocock-course-lanes/lessons/03-compaction-and-auto-compaction.md`), graded against
the verified harness verdicts C1-C6 in the contract's table, the context-guard evidence-degraded
marker and reader contract, and the handoff skill's fork-beats-compaction doctrine. Register
Q24-Q29; answers locked under the user's standing acceptance of this session's recommendations
(register provenance in the topic ledger).

**Dual provenance:** lane 3 was closed by two parallel runs on 2026-08-17 — the contract-branch
run (commit `e064f23f`, filed #2995, these rows) and the chain-branch run (commit `032e4ea4`,
zero items filed, rows in the interim `aihero-core-lanes.md`, dissolved here). Verdicts were
convergent; the chain run's deltas are folded into the two rows and the house-decisions
paragraph below, and both closing summaries stand on issue
[#2901](https://github.com/melodic-software/claude-code-plugins/issues/2901).

| Lesson claim | Ours | Verdict | Reasoning, basis, as-of |
|---|---|---|---|
| Past the smart zone, continuing degrades results slowly; cached tokens are cheaper but the environment is less capable | context-guard zones (smart/acceptable/dumb) + the router's judgment tests | **COVERED** | The operational rule (leave a degraded window) is the zone doctrine; his degradation narrative is bucket-ii material graded against instrumented zone readings plus declared judgment-default bands (A1 baseline), never adopted as numbers. As-of 2026-08-17 |
| Clearing loses the "why"; re-exploration after a bare clear is lossy | Router Q3 reserves `/clear` for disposable context; the handoff save-point exists to carry the why | **COVERED** (stronger) | His lesson compares only continue/clear/compact; the handoff-file fork he introduces one lesson later beats his own trichotomy for the retain-the-why case, which is exactly our fork-beats-compaction ordering. As-of 2026-08-17 |
| Compaction "takes the context, squeezes it down, and seeds a fresh session" | No such claim in the family; compact edge documented as same-session | **REJECT** (harness claim) | Verdict C4 REFUTED (two-pool): compaction continues the SAME session over a structured summary; only fork or `--fork-session` makes a new session id. The lesson and its quiz answer ("seeds a fresh session in memory") both carry the refuted mechanics. As-of 2026-08-17 |
| `/compact [instructions]` steering matters; one sentence is often enough | Router compact edge requires a steering hint naming what the summary must keep | **COVERED** | Verdict C6 CONFIRMED (docs-only, single-pool label carried); parity on the steering discipline, ours phrased as a requirement rather than a tip. As-of 2026-08-17 |
| You can queue messages during compaction; they run when it finishes | Not taught anywhere in the family | **UNKNOWN** (recorded, not taught) | Verdict C5 UNDOCUMENTED in official docs; adjacent evidence suggests a queue exists but its compaction interaction is unspecified. Q28 decision: record now, do not block the lane on a probe neither cloud session can run; probe sketch retained in the contract. As-of 2026-08-17 |
| The compaction summary preserves a structured set (intent, spec, concepts, file refs, errors, user messages, pending tasks) | Handoff structure doc is the deliberate-selection counterpart | **COVERED** (observation) | Recorded as an observation of harness output, not doctrine; our position stands: a summarizer keeps what it happens to keep, a handoff carries what was chosen deliberately. As-of 2026-08-17 |
| Compact-before-QA on finished work is a "cast-iron great" use | PostCompact evidence-degraded marker: a compacted session's effective zone is dumb regardless of numbers | **REJECT** (track-on-event) | Q25: evidence degradation is trigger-independent, the marker's rationale (evidence already gone from the model-visible context) holds for manual and auto alike; his own phase-boundaries lesson routes AFK QA to a subagent, undercutting the case. QA over a compaction summary grades the summary (secondary evidence), never the work — boundary validation routes to a fresh-context subagent (the shipped phase-verifier pattern). The marker is affirmed UNCHANGED today — no boundary-timed carve-out, because a hook cannot observe intent and a conditional marker stops being evidence — but the marker already records `trigger: manual\|auto\|unknown` (post-compact-mark.sh), so consumer differentiation is buildable; revisit ONLY on real evidence that steered boundary-timed compactions perform well (the recorded trigger field is the observable). As-of 2026-08-17 |
| Primary source (the session) vs secondary source (the summary); after compaction nothing is retrievable in full | Constraint re-scan reads the lossless on-disk transcript across compaction (handoff structure doc) | **ADOPT terms / REJECT the irrecoverability half** | Q27: the vocabulary (primary/secondary source) goes to lane-6 adoption; the irrecoverability claim is wrong for Claude Code, where the JSONL transcript persists losslessly on disk and only the model-visible context turns secondary. His quiz answer "compaction writes no file" conflates the two. As-of 2026-08-17 |
| Past the window limit requests error; the harness protects via auto-compact; `/config` shows Auto-compact; `autoCompactWindow` accepts 100,000 to 1,000,000 | Nothing in the family documents this today | **CONFIRMED** (informational) | Verdicts C1-C3 (two-pool incl. the shipped binary schema `min(1e5).max(1e6)`); his 250k example is inside the verified range. UI-surface details recorded as observations. Documentation gap filed: [#2995](https://github.com/melodic-software/claude-code-plugins/issues/2995). As-of 2026-08-17 |
| Auto-compaction exists in every single agent harness | Out of our governance scope | **NOT RELEVANT** (overbroad) | We govern Claude Code only; recorded without a verdict on other harnesses. As-of 2026-08-17 |
| Mid-phase compaction loses the thread (style drift, forgotten features); the boundary is the least-damage point | Router restricts `/compact` to phase boundaries only, ordered last, with steering | **COVERED** | Boundary-only compaction is already house doctrine; his mid-phase anecdotes are bucket-ii anchors with named provenance. As-of 2026-08-17 |
| Auto-compact gives no steering hook; if auto-compact fires something went wrong; the human owns the boundary decision | context-guard instruments the window, renders the continuation menu to the operator only (check I23), optional blocking mode | **ADOPT** (convergent — the diagnostic half; prescriptive half REJECTED) | Q26: same conclusion, one layer further, instrument the environment and route menus to the human rather than only training the human. The parallel chain run split this row explicitly, and the split is the precise form: the diagnostic half ("a firing = a missed boundary") is adopted as an anchor phrase, while the prescriptive half ("the human owns the boundary" / disable auto-compact) is REJECTED — unattended cloud/autonomous sessions have no human at the boundary; the licensed version is the instrumented ladder (observable zones → advisory injection → opt-in blocking gate with a grace budget), and auto-compact stays enabled as the last-resort safety net (a degraded continuation beats a hard stall). Zones-below-trigger guidance and config-surface documentation filed: [#2995](https://github.com/melodic-software/claude-code-plugins/issues/2995). As-of 2026-08-17 |

House decisions recorded alongside the rows (Q24-Q29, 2026-08-17): compact-as-default framing is
rejected and compact stays the router's last-resort fallthrough with mandatory steering
(fork-beats-compaction unchanged); no marker carve-out for steered compactions, with the recorded
trigger field as the track-on-event observable; the auto-compact stance is adopted as convergent
with one filed docs item ([#2995](https://github.com/melodic-software/claude-code-plugins/issues/2995));
primary/secondary-source vocabulary routes to lane 6 carrying the transcript-lossless refinement;
C5 stays recorded-unknown and C6 keeps its single-pool label until an interactive probe runs; the
vendored Boris doctrine (sections 63-64: compact lossy vs clear-plus-brief, rot reported at
300k-400k with the 400000 env-var practice) is cited as vendored nuance, aligned with house
stance, its figures held as named anchors never adopted numbers.

## Lane 4: plan mode / asset rush (issue #2902, decided 2026-08-17)

Basis: the "Why Plan Mode Sucks" lesson (source:
`docs/topics/pocock-course-lanes/lessons/04-why-plan-mode-sucks.md`), graded against
`planning:interview` (pre-clarity stance, auto-detect, auto-guard, `lock` STOP-on-gap, the
general-domain shared-understanding terminal) and `planning:plan` (approval gate, Open Decisions
before the plan body, devils-advocate dispatch, decision confidence gate), plus verdicts C7-C9.
Register Q31-Q35 under the user's restated acceptance.

**Dual provenance:** lane 4 was closed by two parallel runs on 2026-08-17 — the contract-branch
run (commit `de55210d`, these rows) and the chain-branch run (commit `c18d7856`, rows in the
interim `aihero-core-lanes.md`, dissolved here). Verdicts were convergent (asset-rush critique
convergent-validated; the `lock` audit concluded LICENSED EXCEPTION in both); the chain run
additionally filed
[#2997](https://github.com/melodic-software/claude-code-plugins/issues/2997) — eval coverage
regression-gating the lock/auto-guard defenses — which stands. **Coverage landed with this
record:** the two behavioral defenses the item named are gated as of the change that added this
paragraph. Eval cases `lock-halts-on-planted-open-decision` (id 15) and
`auto-residue-asked-or-user-reserved-never-assumed` (id 16) live in
`plugins/planning/skills/interview/evals/evals.json`, each with planted fixtures under
`plugins/planning/skills/interview/evals/fixtures/`; because the marketplace has no model-graded
eval runner yet, the mechanical gate behind them is
`plugins/planning/tests/interview-defenses.test.sh`, which pins both cases and the load-bearing
rule text in the skill body they grade against.

| Lesson claim | Ours | Verdict | Reasoning, basis, as-of |
|---|---|---|---|
| Agents rush from prompt to implementation with no alignment step (the asset rush) | `planning:interview` is the pipeline's pre-clarity stage: a contract locked before exploration, planning, or execution | **COVERED** (convergent) | The critique is the design rationale the pipeline already embodies; behavior-change work is interview-first by default, with auto-detect keeping it cheap. No change needed, so no work item (reclassified from ADOPT per schema, PR #3008 review). As-of 2026-08-17 |
| Plan mode is a buffer between exploration and implementation: a plan document you review, then proceed | Plan mode is treated as a permission/safety gate; alignment is owned upstream by the interview contract | **COVERED** (position) | The harness feature is not rejected, it is repositioned: a permission mode cannot produce shared understanding, and nothing in the family asks it to. As-of 2026-08-17 |
| "Plan mode is still rushing": the plan reads like the implementation; the decisions are already made and written down | Two structural answers: the Brief locks intent BEFORE `/planning:plan`, and the plan skill itself refuses to lock decisions inline (Open Decisions surfaced before the plan body; a confidence gate routes judgment calls back to interview rounds; user approval gate before any code; fresh-context devils-advocate stress-test) | **COVERED** (convergent, already answered structurally) | His diagnosis names exactly the failure the pipeline's two gates exist to prevent; no change needed, so no work item (reclassified from ADOPT per schema, PR #3008 review). As-of 2026-08-17 |
| Root cause is the sycophantic trait: told to produce, the agent produces | Interview stance: recommendations-first but facts-are-mine/decisions-are-the-user's; the auto-guard forbids resolving a genuine user choice; `/planning:audit-answers` is the producer-not-critic control | **COVERED** | The trait is countered by structure, not exhortation; "sycophancy" and "asset rush" go to lane 6 as term candidates. As-of 2026-08-17 |
| The design concept (Brooks): shared understanding is not an asset; conversation sharpens it | The general-domain interview terminal drives to a shared understanding and STOPS: no Brief, no artifact, no pipeline handoff | **COVERED** (embodied) | Q33: the endpoint already exists; the term maps to our "shared understanding" (lane-6 adoption candidate); no mechanism change earned. As-of 2026-08-17 |
| Walkthrough: cycle `shift+tab` until plan mode is on | Verified harness behavior | **CONFIRMED** | Verdict C7 (two-pool); no fixed press count is taught. As-of 2026-08-17 |
| Walkthrough: "I can view the plan by typing `/plan`" | Verified harness behavior | **REJECT** (stale walkthrough) | Verdict C9 PARTIALLY TRUE: `/plan [description]` ENTERS plan mode; no documented command views the current plan (absence half two-pool; positive half docs-only). The lesson's critique is unaffected by its stale demo. As-of 2026-08-17 |
| Walkthrough: review the generated plan, modify, then proceed (approval flow) | Verified harness behavior | **CONFIRMED** | Verdict C8 (two-pool; flow details docs-only); the newer EnterPlanMode tool postdates the lesson. As-of 2026-08-17 |
| "A different approach" replaces this (the grilling tease) | Lane 5's subject | **NOT RELEVANT** (here) | Graded in the grilling-parity lane (#2903). As-of 2026-08-17 |

House decisions recorded alongside the rows (Q31-Q35, 2026-08-17): the `lock`/auto-synthesize
audit concludes LICENSED EXCEPTION, not quiet rush: the auto-guard bars synthesizing genuine
user decisions, `lock` is user-invoked (the invocation is the confirmation) with STOP-on-gap,
the default action leans to relentless interviewing, and `/planning:audit-answers` supplies the
producer-not-critic check (exercised live in this effort, where it corrected two decisions).
This run decided no plugin change; the parallel chain run filed the one lane 4 work item,
[#2997](https://github.com/melodic-software/claude-code-plugins/issues/2997) (regression evals
for the four lock/auto-guard structural defenses) — whose eval-case and tripwire-suite pointers
are recorded in "Dual provenance" above. Lane-6 parcels are the three term candidates
(design concept mapped to shared understanding, asset rush, sycophancy) and coverage phrasing.

## Lane 5: grilling-interview parity (issue #2903, decided 2026-08-17)

Basis: "The Grill-Execute-Clear Loop" lesson (source:
`docs/topics/pocock-course-lanes/lessons/05-grill-execute-clear.md`, the verbatim paste the
maintainer committed to the contract-branch topic slice — pruned when that slice merges, so the
as-of date is the durable anchor), graded against `planning:interview` and against his CURRENT
repo texts read from a live clone at HEAD `068b6e0` (`skills/productivity/grilling/SKILL.md`,
`grill-me/SKILL.md`) — which match the SSOT-recorded baseline verbatim in substance, confirming
the 2026-08-17 recheck's cosmetic-only-drift finding. Register Q36-Q37 under the user's
restated acceptance. The grilling-family provenance itself is settled in
`mattpocock-skills.md` rows 3-4 and is confirmed here, not re-derived.

**Dual provenance and audit supersession:** lane 5 was closed by two parallel runs — the
chain-branch run (commit `069b7f9d`, 2026-08-18 03:20Z, closed
[#2903](https://github.com/melodic-software/claude-code-plugins/issues/2903)) and this
contract-branch run (commit `723e7830`, 03:26Z). The chain run graded against the upstream repo
primaries only (its container could not reach the lesson) and ran a two-validator
`/planning:audit-answers` pass that OVERTURNED the provisional zero-work-items answer and
corrected two evidence attributions; this run had the lesson paste but predates that audit.
The merged record below keeps this run's lesson-grounded rows and supersedes them with the
chain audit's corrections where they conflict: the audit-backed rows (including the two filed
via [#2998](https://github.com/melodic-software/claude-code-plugins/issues/2998)) are
upstream-repo-grounded and stand regardless of lesson text, while this run's lesson basis cures
the chain record's "course side UNVERIFIED" caveat on the clear step.

| Lesson claim | Ours | Verdict | Reasoning, basis, as-of |
|---|---|---|---|
| The skill interviews you relentlessly until shared understanding; only then do you implement | `me`-mode canonical framing + the confirmation gate ("do not act on the interview's output until they confirm") | **COVERED** (attributed) | The recorded behavioral derivation (SSOT rows 3-4); ours adds the mechanical register gate script on top of the judgment stop. As-of 2026-08-17 |
| Design tree; rounds; the frontier is every decision whose prerequisites are settled, asked all at once; a dependent question waits for a later round | Frontier-rounds loop, identical in substance | **COVERED** (attributed) | Same derivation record; his current repo text matches the audited baseline. "Design tree" and our "decision tree" are equivalent vocabulary, no action. As-of 2026-08-17 |
| Per-question format with a recommended answer (the emoji-anchored shape) | Recommendation-per-question with a single verdict marker; emoji anchors are the `use_emoji_question_markers` opt-in, default off | **COVERED** (recorded v1.2 adoption) | Decoration of the existing marker, adopted opt-in; nothing new in the lesson. As-of 2026-08-17 |
| Finding facts is your job, never the user's; dispatch a sub-agent, don't block the round; decisions are the user's | Facts-vs-decisions split, background fact sub-agents, non-blocking rounds | **COVERED** (attributed) | Same derivation record, near-verbatim overlap by design. As-of 2026-08-17 |
| Done when the frontier is empty, nothing silently assumed; the user confirms shared understanding first | Stop condition + `check-open-questions.sh` register gate + confirmation gate + auto-guard + unattended ladder | **PARITY+** (corrected by audit; supersedes this run's "COVERED (stronger)") | The chain audit corrected the grading: the user-confirmation gate itself is PARITY — upstream has it verbatim ("Do not act on it until the user confirms"). The genuine house strengtheners are the mechanical register-gate script, the ask-time register + drift check, the testable-acceptance-criteria stop, and me-mode's named-assumption-is-not-a-stop rule. As-of 2026-08-18 |
| The grill-execute-clear loop: understand, execute, clear your mind, next feature | Workflow stages own the shape; the clear leg is the continuation router's territory (clear/handoff chain; spec-first mode runs stages with `/clear` between) | **COVERED**, no term adoption | Q36: a second name for a loop the house taxonomy already owns violates vocabulary parsimony; recorded as a mapping, not a new term. As-of 2026-08-17 |
| Many rounds is the point; keep going until the frontier is empty | No question cap; the escape is the user's wrap-up | **COVERED** (stronger) | House additions his lesson lacks: the ballooning-frontier route to `planning:wayfind` and the question budget scaling with upstream artifacts. As-of 2026-08-17 |
| `grill-me` is a user-invoked pointer that calls the model-invoked `grilling` | One skill, three actions (`me`/`auto`/`lock`), user- and model-invocable under trigger discipline | **COVERED** (different shape, deliberate) | His two-skill split expresses his invocation-reach invariant; our single-skill shape predates it and the difference is recorded, not a gap. As-of 2026-08-17 |
| Walkthrough machinery (npm run reset, `.agents/skills`, the `/` picker) and the lesson-comments example questions | Course-platform machinery and illustration | **NOT RELEVANT** | No repo counterpart owed. As-of 2026-08-17 |
| The loop's "clear" leg (clear your mind between features) | Recommend-clear (never auto-clear) sits post-Brief, licensed by Brief/ledger persistence — which dissolves upstream's own recorded no-ledger complaint | **DELIBERATELY DIFFERENT** (course side resolved) | The chain record carried "course side UNVERIFIED (lesson unreachable)" with a reopen-on-text condition; the condition fired at harvest — the committed lesson paste teaches no clear-step mechanics beyond one sentence plus a dictionary link, so the deliberate difference is confirmed against the actual text and the UNVERIFIED caveat retires. Upstream's own repo docs teach the opposite of a mandatory clear ("Hand the same conversation straight to to-spec"); loop-position nuance recorded. As-of 2026-08-18 |
| Ungrillable question → prototype detour (upstream fires it mid-grilling: "stop grilling… build the throwaway version… come back and answer in one line") | Absent from the interview (grep-confirmed by both audit validators); our route exists only downstream (wayfind / plan / brainstorm) | **ADOPT** (delivered) | Chain audit finding, upstream-repo-grounded. Filed: [#2998](https://github.com/melodic-software/claude-code-plugins/issues/2998); delivered by [#3045](https://github.com/melodic-software/claude-code-plugins/pull/3045) — `interview` now carries the detour in "Mid-interview composition" (routing look-and-feel to `/prototype:explore-directions`, logic/state/data-shape to `/prototype:pressure-test`) plus a **Needs-an-artifact** arm in the `context/loop.md` categorization taxonomy; planning 0.32.0. As-of 2026-08-19 |
| Plan-mode-off while grilling | Beyond upstream's taste point, a mechanical edge the audit surfaced: the ask-time register write is load-bearing and plan mode's read-only enforcement blocks it | **ADOPT** (delivered) | Includes reconciling `planning:plan`'s clarifying-rounds-in-plan-mode sentence with the lane 4 asset-rush doctrine. Filed: [#2998](https://github.com/melodic-software/claude-code-plugins/issues/2998); delivered by [#3045](https://github.com/melodic-software/claude-code-plugins/pull/3045) — the gotcha lands in `interview/context/gotchas.md`, and `plan`'s plan-mode round is now scoped to a scoping confirm with substantive rounds routed to `/planning:interview` outside plan mode; planning 0.32.0. As-of 2026-08-19 |
| Provenance correction (adjacent, from the chain audit) | SSOT PR-#532 row | **CORRECTED in SSOT** | The row's "ADR 3-gate + glossary purity are house additions" claim is contradicted on current upstream main (`domain-modeling` carries both near-identically); annotated as convergent-or-derived, direction unverifiable. As-of 2026-08-18 |

House decisions recorded alongside the rows (Q36-Q37 this run; chain audit 2026-08-18): no term
adoption for the loop name (mapping recorded instead — see the term-adoption section); the
zero-work-items claim this run recorded was OVERTURNED by the chain audit
([#2998](https://github.com/melodic-software/claude-code-plugins/issues/2998) filed); two
cosmetic unadopted deltas noted, deliberately unfiled (upstream's bolded question-title slot;
his answer-the-recommendation polarity note); no new lane-6 parcels beyond the
design-tree/decision-tree equivalence note.

## Steering lanes 7–9 (issues #2909–#2911, decided 2026-08-17)

The course's Steering section (nine lessons, pasted and inventoried in the 2026-08-17
steering-section session) was vetted as three additional lanes under the same contract rules.
Rows below are carried from the interim steering record (`aihero-steering-lanes.md`, graduated
from the chain's contract slice at chain close and dissolved into this document) in that
record's three-column form; each section preamble carries the basis and as-of, and the
divergence-at-re-fetch trigger discipline applies unchanged. Session outcome recorded there:
the SSOT's `writing-for-agents` rejection was re-evaluated and superseded (parity holds only
for the pruning/audit half; section-by-section verdicts live in the SSOT decomposition table).

Lesson key: 1 The Steering Map · 2 Steering With A Pointer · 3 What Are Agent Skills ·
4 Write A Skill · 5 User Vs Project Skills · 6 Navigation Pointers · 7 Pruning ·
8 Trying Out Pruning · 9 Claude Code's Automatic Memory.

### Lane 7: authoring doctrine (issue #2909, closed 2026-08-17)

Interview-first per contract; register gate clean (12/12); user confirmed. Design contract:
`docs/specs/write-for-agents-brief.md`. Lessons 1, 2, 4 (authoring half), 7. As-of 2026-08-17.

| Claim / concern (lesson) | Verdict | Detail |
|---|---|---|
| Authoring-time doctrine needs a firing home at the writing moment (L1, L2, L4) | ADOPT | New skill `docs-hygiene:write-for-agents` — model-invoked, write-side complement to the audit siblings; design contract in the topic PLAN.md; built via filed implementation issues |
| Scope = agent-consumed docs (L4) | ADOPT (generalized) | User-widened beyond upstream's skills/AGENTS.md/CLAUDE.md: any agent-consumed markdown in the repo; auto-read surfaces are the high-value core, grounded in a docs-verified enumeration (research artifact in topic memory slice; adapted into the skill's reference) |
| Completion-criteria doctrine (L4) | ADOPT (both moments) | Write-side in the new skill; audit-side as a new `skill-quality:check` criterion so the existing fleet gets graded too |
| Two loads — cognitive load as budget (L1) | ADOPT | Doctrine operates in the skill body; PLUGIN-PHILOSOPHY Instruction economy gains a one-line cross-reference |
| Leading words + negation (L4) | ADOPT | Folded into the skill design; SSOT tracked strand retires when the implementation merges (cross-links the interview-batch-rounds deferral) |
| Pointer wording: cover branches, front-load leading word (L2) | ADOPT (adapted) | Inline in the skill; pointer-quality criteria stay pointed-at in `audit-progressive-disclosure` |
| Trigger enforcement via hook (session-start or otherwise) | REJECT | Probable overengineering (user-decided); trigger reliability instead gated by a shipped plugin-eval suite — positives per trigger family fire, negative controls don't, all-pass gates the implementation PR |
| Vendoring/wrapping upstream `writing-for-agents` | REJECT | Adapted new skill, house doctrine and naming grammar; SSOT decomposition table carries provenance |
| Pruning doctrine (L7) | PARITY — no work | Three pruning tests confirmed covered at parity or stronger (SSOT decomposition table: extract-ssot, audit-derivability, audit-instructions/unhobble) |
| Cross-skill invocation phrasing (upstream `.agents/invocation.md`) | ROUTE | Handed to lane 6; decided there — see the term-adoption and doctrine section below |

Lane 7 closed with Brief locked (`docs/specs/write-for-agents-brief.md`), surface enumeration
committed (`docs/specs/agent-doc-surfaces.md`), build filed as
[#2962](https://github.com/melodic-software/claude-code-plugins/issues/2962) and
[#2963](https://github.com/melodic-software/claude-code-plugins/issues/2963), SSOT annotated.

### Lane 8: invocation mode (issue #2910, closed 2026-08-17)

Interview-first per contract; register gate clean (8/8); user confirmed. Contract:
`docs/specs/invocation-mode-doctrine-brief.md`. Rubric (the doctrine artifact):
`docs/conventions/invocation-mode/README.md`. Lessons 3, 4 (invocation half), 5. As-of
2026-08-17.

| Claim / concern (lesson) | Verdict | Detail |
|---|---|---|
| Invocation choice needs a decision rubric (L3, L4) | ADOPT (adapted — inverted default) | Rubric adopted with model-invoked default + three exception classes (side-effect/manual-timing, setup, maintainer-only) — the inverse of upstream's user-invoked default. Home: `docs/conventions/invocation-mode/README.md` + convention-registry row; cross-linked from PLUGIN-PHILOSOPHY (setup contract, Instruction economy); `playbooks:skill-authoring` pointer filed |
| Upstream's user-invoked default (L4) | REJECT | Solo-operator posture; materially weakened by mattpocock/skills#693 (desktop/web drop user-invoked skills from the listing) and by this marketplace's multi-repo discoverability need |
| Splitting by invocation (L4) | ADOPT (routed) | The rubric owns the split axis; `docs-hygiene:write-for-agents` (#2962) when-to-split doctrine points at it (lane 7 decision honored) |
| Router-skill pattern (L4 / MECHANICS) | REJECT (with reason) | Under the model-invoked default the always-present listing IS the router; `disable-model-invocation: true` skills are deliberately model-invisible. Human-side answer: `docs/SKILL-CHEAT-SHEET.md` + `claude-ops:inventory`. Domain-scoped composition routers (`discipline:sweep-all` precedent) remain an admitted distinct pattern |
| Explicit `disable-model-invocation` on every skill (L4) | ADOPT | 17 missing-key skills normalized to explicit `false` + new `skill-quality:check` criterion requiring the key — filed implementation follow-on |
| Setup-skill convention (L3/L4) | PARITY — no work | Already documented: PLUGIN-PHILOSOPHY "Setup is explicit and repeatable" (landed `967db56c`, pre-dating #2910's "documented nowhere" premise) |
| User vs project scope + cloud caveat (L5) | ADOPT | Remote/cloud sessions never load `~/.claude` user scope — project/marketplace skills are the only steering that reaches them; recorded as the rubric's surface-coverage/cloud-scope evidence axis |
| Invocation-reach invariant (MECHANICS) | CONFIRMED | Docs-verified 2026-08-17 (`true` → model-invisible everywhere, human `/name` only); SSOT strand records CONFIRMED with the audit-side trigger kept, upstream-release trigger retired |

Fleet re-grade (ADR 0005-bounded, executed in-lane): 10 non-setup `true` skills graded — 9
KEEP, 1 FLIP (`planning:questionnaire` → model-invoked). Lane 8 closed with the rubric homed,
enforcement filed
([#2968](https://github.com/melodic-software/claude-code-plugins/issues/2968): explicit-key
normalization + `skill-quality:check` criterion), the flip filed
([#2969](https://github.com/melodic-software/claude-code-plugins/issues/2969)), SSOT gap-3
rows dispositioned and strand CONFIRMED.

### Lane 9: steering validations (issue #2911, closed 2026-08-17)

Interview-first per contract; rounds 1–2 user-confirmed. No separate topic Brief — lane 9
designs nothing; these rows plus filed items are the record. Lessons 6, 8, 9 + leftovers of
1–2. As-of 2026-08-17.

| Claim / concern (lesson) | Verdict | Detail |
|---|---|---|
| Navigation sections in CLAUDE.md ("highways") vs audit C5 flagging codebase descriptions (L6) | ADOPT (adapted) | Filed criteria patch: C5 carve-out distinguishing curated navigation pointers to non-obvious, load-bearing docs (KEEP branch) from file-by-file inventories Claude can rebuild (still FLAG). Marked as repo extension if official docs state no navigation posture (provenance rule: `update` must not overwrite) |
| Stale-pointer risk — "a stale highway is worse than no highway" (L6) | PARITY — no new check | `claude-memory:audit` C7 already FAILs on referenced paths that do not exist; the filed patch adds a one-line C7 note naming stale pointers as the standing cost of navigation sections |
| Nested/subdirectory CLAUDE.md as a placement destination (our extension; course omits it) | ADOPT | C3 placement-table row ("subdirectory-specific conventions → nested CLAUDE.md") in the same filed patch; loading-semantics wording gated on harness-claim verification |
| @-mention as the one-turn-scoped pointer equivalent (L2/L6) | ADOPT | One-line distinction on C3's import row: conversational @-mention is one-turn steering, cheaper than a permanent pointer for one-off needs; `@path` imports in CLAUDE.md load at launch (already priced). Same filed patch |
| Design-smell caveat: a pointer mirroring changes across distant folders can mask low cohesion (user-raised) | ADOPT | Homed in the criteria patch's remediation guidance (restructure-before-pointer consideration at the audit's fix moment); coordination comment on [#2962](https://github.com/melodic-software/claude-code-plugins/issues/2962) points the authoring skill at it — no duplicated doctrine |
| /init-then-prune eval fixture (L8, user-suggested) | ADOPT | Filed against `claude-memory:audit`'s existing eval suite: static bloated-CLAUDE.md fixture (the shape `/init` produces) in the eval's `files`, graded against expected findings (C1/C2/C5); regression gate on audit judgment quality. Static fixture chosen over live `/init` generation (determinism) |
| Auto-memory territory (L9) | PARITY — no work | `claude-memory:audit` M1–M4 plus the `stateless` skill cover the lesson; `official-guidance.md` carries doc-sourced quotes (updated 2026-08-15). The course's one inaccuracy (cwd- vs repo-keying) is carried by harness verdict row 1 below — parity rows point at it, no duplicate |
| `~/.agents/skills` as an equivalent personal-skills path (L1–2/L5 leftover) | REJECT — do-not-repeat | REFUTED (harness verdict row 5, two-pool): the path is OpenCode's agent-compatible convention; docs, shipped binary, and changelog are all silent for Claude Code. Must never enter our docs as a Claude Code path |
| Remaining L1–2 leftover claims (steering surfaces: `/memory`, MEMORY.md index, `/context` accounting, agentskills.io standard) | ADOPT (verdict-backed, no work) | Covered by harness verdict rows 2–3, 6–7; existing guidance already aligns — rows only, no work items (user-decided, Q8) |
| Term candidates increment (L6) | ROUTE | "highway / stale highway" handed to lane 6; decided in the term-adoption section below |

Lane 9 closed with the criteria patch filed
([#2987](https://github.com/melodic-software/claude-code-plugins/issues/2987)), the eval
fixture filed
([#2989](https://github.com/melodic-software/claude-code-plugins/issues/2989)), and the
harness-claims verdicts below.

## Harness-claims verdicts (graduated durable record)

### C1–C9 (verified 2026-08-17; graduated from the contract PLAN.md)

Research run gated clean (artifact + coverage gates exit 0); fresh-context verifier graded
corroboration; parent cured C3 with a binary-schema probe. Graduated verbatim from
`docs/topics/pocock-course-lanes/PLAN.md` ("Harness-claims verdicts", branch
`claude/plan-mode-discussion-55kszx`) so the citable record survives that branch's lifecycle.
**Caveat carried at graduation:** C8's confirmation rests on this table alone (the memory-tier
research artifacts are disposable and the verdict was not re-reproduced by the later audit
passes) — re-verify C8 against current official docs rather than chain-citing this row as
independent corroboration.

| # | Course claim | Verdict | Corroboration |
|---|---|---|---|
| C1–C2 | `autoCompactWindow` exists; controls when auto-compact fires | CONFIRMED | two-pool (docs + binary) |
| C3 | range 100,000–1,000,000 tokens | CONFIRMED | two-pool (docs + binary schema `min(1e5).max(1e6)`) |
| C4 | compaction "seeds a fresh session" | **REFUTED** — same session continues over a structured summary; only fork/`--fork-session` makes a new session ID | two-pool |
| C5 | messages queue during compaction | UNDOCUMENTED — verify empirically before teaching | n/a |
| C6 | `/compact [instructions]` accepts focus instructions | CONFIRMED | single-pool (docs only) |
| C7 | Shift+Tab cycling / `--permission-mode plan` entry | CONFIRMED (no fixed press count) | two-pool |
| C8 | ExitPlanMode approval flow (+ newer EnterPlanMode tool) | CONFIRMED (flow details docs-only) | two-pool |
| C9 | `/plan` views the current plan | PARTIALLY TRUE — `/plan [description]` exists but ENTERS plan mode; no documented command views the plan | absence half two-pool; positive half docs-only |

Cures for the single-pool rows when convenient: run `/compact <instructions>` and `/plan` in a
live interactive session (Tier-0).

### Lane 9 steering claims (verified 2026-08-17 against Claude Code v2.1.233)

Docs + shipped binary + changelog as evidence pools; fresh-context verifier pass with parent
cure attempts — labels carry the verifier's scoping corrections. The
`disable-model-invocation` listing claim was verified in lane 8 (SSOT strand) and is reused,
not re-verified.

| # | Course claim | Verdict | Corroboration |
|---|--------------|---------|---------------|
| 1 | Auto-memory lives in a per-project state directory outside the repo, keyed by cwd | PARTIALLY TRUE | two-pool for location (`~/.claude/projects/<project>/memory/`: docs + binary); keying is git-repo-derived since v2.1.63 — worktrees/subdirectories share one store; project root only outside git repos (docs + changelog) |
| 2 | `/memory` opens memory files | CONFIRMED (as documented) | two-pool for the command (docs + binary); enumerated behaviors (scope listing, auto-memory toggle, open-folder, GUI non-blocking since v2.1.216) docs-only |
| 3 | MEMORY.md is a concise index; first 200 lines / 25KB load at session start; topic files on demand | CONFIRMED | two-pool for the 200-line half (docs + binary `FZ=200`); 25KB half docs + changelog v2.1.83; over-limit writes succeed with rewrite error (v2.1.210) |
| 4 | Subdirectory CLAUDE.md loads on demand when files in that subtree are read; ancestors in full at launch; nested not re-injected after `/compact` | CONFIRMED | single-pool (docs-only — changelog v2.1.69/v2.1.89 presuppose rather than state the semantics; binary probe unresolved; remote live-probe cure failed on confounds). Cure when convenient: live probe with a tracked nested CLAUDE.md in a local interactive session |
| 5 | `~/.agents/skills` is an equivalent personal-skills path to `~/.claude/skills` | REFUTED | two-pool refutation (docs enumerate only `~/.claude/skills`; binary has no `.agents` filesystem path; OpenCode's upstream doc owns the convention) |
| 6 | Agent Skills is an open standard documented at agentskills.io | CONFIRMED | two-pool (official docs link it; spec repo `agentskills/agentskills` README — "Anthropic-originated" is the spec repo's self-report; agentskills.io itself egress-blocked from the verifying container, verified via the spec repo) |
| 7 | `/context` reports "Memory files" as its own accounting category | CONFIRMED | two-pool (docs instruction + binary category push). Open sub-detail, non-blocking: whether the auto-memory MEMORY.md slice counts inside that row is undocumented |

## Term adoption (lane 6, decided 2026-08-18)

Course-dictionary and lesson vocabulary graded for entry into this project's ubiquitous
language. Adoption decisions were made in-lane (register + two-validator audit pass); glossary
materialization routed through `/domain-driven-design:curate-language`, whose
convention-resolution ladder found no existing project glossary and more than one plausible
home, so creation was deferred to a filed follow-on rather than invented in-lane
([#3000](https://github.com/melodic-software/claude-code-plugins/issues/3000)). That is now
**done**: the maintainer confirmed the placement and the ADOPTED terms live in
[`docs/GLOSSARY.md`](../GLOSSARY.md), which also records the REJECT rows below as rejected
synonyms mapped to the terms that own their concepts. The rows here remain the decision record —
the glossary carries the vocabulary, this table carries why.

| Term | Verdict | Basis |
|---|---|---|
| primary source / secondary source | **ADOPT** (canonical pair) | Convergent with the save-point engine's lossless-transcript-vs-model-visible-conversation rule; routed here by lanes 2–3 carrying the transcript-lossless refinement (the on-disk JSONL transcript stays primary across compaction; only the model-visible context turns secondary) |
| phase boundary | **ADOPT** | Already operative house usage (the continuation router runs "at a phase boundary"); adoption formalizes it |
| smart zone | **ADOPT** | Already context-guard's zone name (smart/acceptable/dumb); his folklore budget figures stay rejected as numbers (claim-ladder bucket ii, amendment A1) |
| AFK criterion | **ADOPT** (adapted) | The router-edge name lane 2 adopted (autonomous-feasibility test pointing to `session-flow:orchestrate`); admission licensed by its distinct project meaning |
| asset rush | **ADOPT** | Failure-mode name already operative in lane 4's rows and the chain records; names the critique the interview-first pipeline answers |
| context load / cognitive load (the two loads) | **ADOPT** | Adopted into the `docs-hygiene:write-for-agents` design by lane 7 (#2962); recorded as vocabulary riding that design |
| navigation pointer | **ADOPT** | Lane 9 adopted the criteria under this name (#2987); the canonical term for curated CLAUDE.md navigation entries |
| design concept | **REJECT** (mapping recorded) | Maps to our existing "shared understanding" (lane 4, Q33); a second name for an owned concept violates vocabulary parsimony |
| sycophancy | **REJECT** (as project vocabulary) | Generic LLM-behavior term with no distinct project meaning (glossary admission rule); free-prose use unaffected |
| sediment | **REJECT** | Collides with the code-sense use in `playbooks:fable-5` execution doctrine; the pruning concept is covered by the docs-hygiene audit family |
| cache (doc-restating-environment sense) | **REJECT** (with mapping) | The term is heavily overloaded here (plugin cache, prompt cache); the concept is `docs-hygiene:audit-derivability`'s derivable-from-environment doctrine (mapping noted at v1.2-map row 40) |
| push vs point | **COVERED** | Existing house term "point, don't copy" (`discipline:point-dont-copy`) owns the concept |
| highway / stale highway | **REJECT** (as canonical) | Metaphor duplicating "navigation pointer"; survives only as the quoted mnemonic in #2987's C7 note |
| grill-execute-clear (loop name) | **REJECT** (mapping recorded) | Lane 5 Q36: a second name for a loop the house workflow taxonomy already owns |
| design tree | **EQUIVALENT** (no action) | Lane 5: equivalent to our "decision tree"; recorded, nothing to adopt |

**Cross-skill invocation phrasing (the routed lane 7 candidate):** ADOPT (adapted). Upstream
standardized cross-skill dependencies on explicit "Call the Skill tool with \"name\"" phrasing
(`.agents/invocation.md`, PRs #878/#880), on his measured claim — his repo's measurement, named
provenance, bucket ii — that it outperforms bare `/name` prose. This fleet practices the
equivalent in part ("invoke `/plugin:skill` via the Skill tool" appears across the verification
and implementation families) but the practice was mixed — several operative chains hand off
bare — and codified nowhere; the doctrine now lives in
`docs/conventions/invocation-mode/README.md` ("Cross-skill invocation phrasing"), added by this
lane and scoped to new/edited text, with the fleet normalization sweep filed as
[#3002](https://github.com/melodic-software/claude-code-plugins/issues/3002). The sweep landed
2026-08-21; the scoping note is retired and the rule is now unconditional.

## Coverage index (the journey's completion gate)

One row per course lesson vetted by this effort; every opinionated claim in each lesson maps to
a decision row, a filed work item, or an explicit not-relevant note in the named lane section.
Filed items across all lanes, by lane:

- Lane 1: issues #2955, #2956, #2957
- Lane 2: issues #2971, #2972, #2973
- Lane 3: issue #2995
- Lane 4: issue #2997
- Lane 5: issue #2998
- Lane 7: issues #2962, #2963
- Lane 8: issues #2968, #2969
- Lane 9: issues #2987, #2989
- Lane 6: issue #3000 (glossary materialization, deferred by the curate-language ladder)

| # | Lesson | Lane(s) | Disposition |
|---|--------|---------|-------------|
| 1 | Handoff | 1 | 9 rows + 2 house decisions; filed #2955, #2956, #2957 |
| 2 | Clear, Compact, Handoff, Or Subagent (phase boundaries) | 2 | 10 rows + house router/autonomy decisions; filed #2971, #2972, #2973 |
| 3 | Compaction | 3 | 12 merged rows (dual-run, reconciled above); filed #2995 |
| 4 | Auto-Compaction | 3 | Covered by the same merged lane 3 record (the lane merged both lessons by contract design) |
| 5 | Why Plan Mode Sucks | 4 | 9 rows + LICENSED-EXCEPTION house audit; filed #2997 |
| 6 | The Grill-Execute-Clear Loop | 5 | 13 merged rows (dual-run + audit supersession, reconciled above); filed #2998 |
| 7 | The Steering Map (S1) | 7, 9 | Lane 7 rows (two loads, authoring home); lane 9 leftovers row |
| 8 | Steering With A Pointer (S2) | 7, 9 | Lane 7 pointer-wording row; lane 9 @-mention row |
| 9 | What Are Agent Skills (S3) | 8 | Rubric + setup-convention + agentskills.io verdict (row 6) |
| 10 | Write A Skill (S4) | 7, 8 | Authoring half in lane 7; invocation half in lane 8 |
| 11 | User Vs Project Skills (S5) | 8 | Scope + cloud caveat row; `~/.agents/skills` refutation (row 5) |
| 12 | Navigation Pointers (S6) | 9 | C5 carve-out, stale-pointer, nested-CLAUDE.md, design-smell rows; filed #2987 |
| 13 | Pruning (S7) | 7 | Parity row (three pruning tests covered) |
| 14 | Trying Out Pruning (S8) | 9 | /init-then-prune eval fixture; filed #2989 |
| 15 | Claude Code's Automatic Memory (S9) | 9 | Auto-memory parity row + harness verdicts 1–3, 7 |

No lesson claim is silently dropped: the original six lessons' claims are enumerated
row-by-row in lanes 1–5 (including the walkthrough machinery NOT-RELEVANT notes), and the nine
steering lessons' claims are enumerated in lanes 7–9 with their leftover claims explicitly
swept (lane 9's L1–2 leftover row and verdict table). The one formerly-tracked coverage gap —
lane 5's "course side UNVERIFIED" clear-step row — was resolved at harvest against the
committed lesson paste (see lane 5).
