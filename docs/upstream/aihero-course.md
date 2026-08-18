# Upstream source: AI Hero course lessons (Matt Pocock)

Provenance record for everything in this marketplace vetted against the AI Hero course lessons
(Matt Pocock's course on working with coding agents). This is a distinct source from the
[mattpocock/skills](https://github.com/mattpocock/skills) repository, whose record is the SSOT at
[mattpocock-skills.md](mattpocock-skills.md): the course is prose lessons with no releases, tags,
or changelogs, so it needs its own recheck regime. Where a lesson restates something the skills
repo also ships, the row cites both bases.

Vetting ran as six lanes on the `pocock-course-lanes` contract
(issues [#2899](https://github.com/melodic-software/claude-code-plugins/issues/2899) through
[#2904](https://github.com/melodic-software/claude-code-plugins/issues/2904)). Lanes decide but
never implement: every ADOPT row points at a filed work item; changes execute through the normal
pipeline.

## Row schema (fixed at creation, per amendment A2)

Each row is a four-part record per
[docs/conventions/upstream-drift/README.md](../conventions/upstream-drift/README.md): the claim,
the basis it was derived against, the as-of date, and a recheck trigger. Columns:

| Lesson claim | Ours | Verdict | Reasoning, basis, as-of |

Verdicts: **ADOPT** (with the filed work item), **REJECT** (with reason), **TRACK** (on a named
event), **COVERED** (already present at parity or stronger, with evidence).

**Recheck trigger, all rows (fixed at creation):** divergence at re-fetch. A read-time re-fetch
of the row's basis (the lesson text, or the upstream artifact the row cites) finds the source no
longer matching the record; the divergence, never the lookup, fires the row, and a firing follows
the upstream-drift maintenance procedure. A row may state a stronger trigger inline; bare "when
the lesson updates" is not a valid trigger form here because the course publishes no observable
update signal.

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

| Lesson claim | Ours | Verdict | Reasoning, basis, as-of |
|---|---|---|---|
| Past the smart zone, continuing degrades results slowly; cached tokens are cheaper but the environment is less capable | context-guard zones (smart/acceptable/dumb) + the router's judgment tests | **COVERED** | The operational rule (leave a degraded window) is the zone doctrine; his degradation narrative is bucket-ii material graded against instrumented zone readings plus declared judgment-default bands (A1 baseline), never adopted as numbers. As-of 2026-08-17 |
| Clearing loses the "why"; re-exploration after a bare clear is lossy | Router Q3 reserves `/clear` for disposable context; the handoff save-point exists to carry the why | **COVERED** (stronger) | His lesson compares only continue/clear/compact; the handoff-file fork he introduces one lesson later beats his own trichotomy for the retain-the-why case, which is exactly our fork-beats-compaction ordering. As-of 2026-08-17 |
| Compaction "takes the context, squeezes it down, and seeds a fresh session" | No such claim in the family; compact edge documented as same-session | **REJECT** (harness claim) | Verdict C4 REFUTED (two-pool): compaction continues the SAME session over a structured summary; only fork or `--fork-session` makes a new session id. The lesson and its quiz answer ("seeds a fresh session in memory") both carry the refuted mechanics. As-of 2026-08-17 |
| `/compact [instructions]` steering matters; one sentence is often enough | Router compact edge requires a steering hint naming what the summary must keep | **COVERED** | Verdict C6 CONFIRMED (docs-only, single-pool label carried); parity on the steering discipline, ours phrased as a requirement rather than a tip. As-of 2026-08-17 |
| You can queue messages during compaction; they run when it finishes | Not taught anywhere in the family | **UNKNOWN** (recorded, not taught) | Verdict C5 UNDOCUMENTED in official docs; adjacent evidence suggests a queue exists but its compaction interaction is unspecified. Q28 decision: record now, do not block the lane on a probe neither cloud session can run; probe sketch retained in the contract. As-of 2026-08-17 |
| The compaction summary preserves a structured set (intent, spec, concepts, file refs, errors, user messages, pending tasks) | Handoff structure doc is the deliberate-selection counterpart | **COVERED** (observation) | Recorded as an observation of harness output, not doctrine; our position stands: a summarizer keeps what it happens to keep, a handoff carries what was chosen deliberately. As-of 2026-08-17 |
| Compact-before-QA on finished work is a "cast-iron great" use | PostCompact evidence-degraded marker: a compacted session's effective zone is dumb regardless of numbers | **REJECT** (track-on-event) | Q25: evidence degradation is trigger-independent, the marker's rationale (evidence already gone from the model-visible context) holds for manual and auto alike; his own phase-boundaries lesson routes AFK QA to a subagent, undercutting the case. The marker already records `trigger: manual\|auto\|unknown` (post-compact-mark.sh), so consumer differentiation is buildable; revisit ONLY on real evidence that steered boundary-timed compactions perform well (the recorded trigger field is the observable). As-of 2026-08-17 |
| Primary source (the session) vs secondary source (the summary); after compaction nothing is retrievable in full | Constraint re-scan reads the lossless on-disk transcript across compaction (handoff structure doc) | **ADOPT terms / REJECT the irrecoverability half** | Q27: the vocabulary (primary/secondary source) goes to lane-6 adoption; the irrecoverability claim is wrong for Claude Code, where the JSONL transcript persists losslessly on disk and only the model-visible context turns secondary. His quiz answer "compaction writes no file" conflates the two. As-of 2026-08-17 |
| Past the window limit requests error; the harness protects via auto-compact; `/config` shows Auto-compact; `autoCompactWindow` accepts 100,000 to 1,000,000 | Nothing in the family documents this today | **CONFIRMED** (informational) | Verdicts C1-C3 (two-pool incl. the shipped binary schema `min(1e5).max(1e6)`); his 250k example is inside the verified range. UI-surface details recorded as observations. Documentation gap filed: [#2995](https://github.com/melodic-software/claude-code-plugins/issues/2995). As-of 2026-08-17 |
| Auto-compaction exists in every single agent harness | Out of our governance scope | **NOT RELEVANT** (overbroad) | We govern Claude Code only; recorded without a verdict on other harnesses. As-of 2026-08-17 |
| Mid-phase compaction loses the thread (style drift, forgotten features); the boundary is the least-damage point | Router restricts `/compact` to phase boundaries only, ordered last, with steering | **COVERED** | Boundary-only compaction is already house doctrine; his mid-phase anecdotes are bucket-ii anchors with named provenance. As-of 2026-08-17 |
| Auto-compact gives no steering hook; if auto-compact fires something went wrong; the human owns the boundary decision | context-guard instruments the window, renders the continuation menu to the operator only (check I23), optional blocking mode | **ADOPT** (convergent) | Q26: same conclusion, one layer further, instrument the environment and route menus to the human rather than only training the human. Zones-below-trigger guidance and config-surface documentation filed: [#2995](https://github.com/melodic-software/claude-code-plugins/issues/2995). As-of 2026-08-17 |

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

| Lesson claim | Ours | Verdict | Reasoning, basis, as-of |
|---|---|---|---|
| Agents rush from prompt to implementation with no alignment step (the asset rush) | `planning:interview` is the pipeline's pre-clarity stage: a contract locked before exploration, planning, or execution | **ADOPT** (convergent) | The critique is the design rationale the pipeline already embodies; behavior-change work is interview-first by default, with auto-detect keeping it cheap. As-of 2026-08-17 |
| Plan mode is a buffer between exploration and implementation: a plan document you review, then proceed | Plan mode is treated as a permission/safety gate; alignment is owned upstream by the interview contract | **COVERED** (position) | The harness feature is not rejected, it is repositioned: a permission mode cannot produce shared understanding, and nothing in the family asks it to. As-of 2026-08-17 |
| "Plan mode is still rushing": the plan reads like the implementation; the decisions are already made and written down | Two structural answers: the Brief locks intent BEFORE `/planning:plan`, and the plan skill itself refuses to lock decisions inline (Open Decisions surfaced before the plan body; a confidence gate routes judgment calls back to interview rounds; user approval gate before any code; fresh-context devils-advocate stress-test) | **ADOPT** (convergent, already answered structurally) | His diagnosis names exactly the failure the pipeline's two gates exist to prevent; no change needed. As-of 2026-08-17 |
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
producer-not-critic check (exercised live in this effort, where it corrected two decisions). No
work items filed: no plugin change was decided; lane-6 parcels are the three term candidates
(design concept mapped to shared understanding, asset rush, sycophancy) and coverage phrasing.

## Lane 5: grilling-interview parity (issue #2903, decided 2026-08-17)

Basis: "The Grill-Execute-Clear Loop" lesson (source:
`docs/topics/pocock-course-lanes/lessons/05-grill-execute-clear.md`), graded against
`planning:interview` and against his CURRENT repo texts read from a live clone at HEAD
`068b6e0` (`skills/productivity/grilling/SKILL.md`, `grill-me/SKILL.md`) — which match the
SSOT-recorded baseline verbatim in substance, confirming the 2026-08-17 recheck's
cosmetic-only-drift finding. Register Q36-Q37 under the user's restated acceptance. The
grilling-family provenance itself is settled in `mattpocock-skills.md` rows 3-4 and is
confirmed here, not re-derived.

| Lesson claim | Ours | Verdict | Reasoning, basis, as-of |
|---|---|---|---|
| The skill interviews you relentlessly until shared understanding; only then do you implement | `me`-mode canonical framing + the confirmation gate ("do not act on the interview's output until they confirm") | **COVERED** (attributed) | The recorded behavioral derivation (SSOT rows 3-4); ours adds the mechanical register gate script on top of the judgment stop. As-of 2026-08-17 |
| Design tree; rounds; the frontier is every decision whose prerequisites are settled, asked all at once; a dependent question waits for a later round | Frontier-rounds loop, identical in substance | **COVERED** (attributed) | Same derivation record; his current repo text matches the audited baseline. "Design tree" and our "decision tree" are equivalent vocabulary, no action. As-of 2026-08-17 |
| Per-question format with a recommended answer (the emoji-anchored shape) | Recommendation-per-question with a single verdict marker; emoji anchors are the `use_emoji_question_markers` opt-in, default off | **COVERED** (recorded v1.2 adoption) | Decoration of the existing marker, adopted opt-in; nothing new in the lesson. As-of 2026-08-17 |
| Finding facts is your job, never the user's; dispatch a sub-agent, don't block the round; decisions are the user's | Facts-vs-decisions split, background fact sub-agents, non-blocking rounds | **COVERED** (attributed) | Same derivation record, near-verbatim overlap by design. As-of 2026-08-17 |
| Done when the frontier is empty, nothing silently assumed; the user confirms shared understanding first | Stop condition + `check-open-questions.sh` register gate + confirmation gate + auto-guard + unattended ladder | **COVERED** (stronger) | Ours makes the empty-frontier judgment mechanically checkable and defines the no-human path his skill leaves open. As-of 2026-08-17 |
| The grill-execute-clear loop: understand, execute, clear your mind, next feature | Workflow stages own the shape; the clear leg is the continuation router's territory (clear/handoff chain; spec-first mode runs stages with `/clear` between) | **COVERED**, no term adoption | Q36: a second name for a loop the house taxonomy already owns violates vocabulary parsimony; recorded as a mapping, not a new term. As-of 2026-08-17 |
| Many rounds is the point; keep going until the frontier is empty | No question cap; the escape is the user's wrap-up | **COVERED** (stronger) | House additions his lesson lacks: the ballooning-frontier route to `planning:wayfind` and the question budget scaling with upstream artifacts. As-of 2026-08-17 |
| `grill-me` is a user-invoked pointer that calls the model-invoked `grilling` | One skill, three actions (`me`/`auto`/`lock`), user- and model-invocable under trigger discipline | **COVERED** (different shape, deliberate) | His two-skill split expresses his invocation-reach invariant; our single-skill shape predates it and the difference is recorded, not a gap. As-of 2026-08-17 |
| Walkthrough machinery (npm run reset, `.agents/skills`, the `/` picker) and the lesson-comments example questions | Course-platform machinery and illustration | **NOT RELEVANT** | No repo counterpart owed. As-of 2026-08-17 |

House decisions recorded alongside the rows (Q36-Q37, 2026-08-17): no term adoption for the
loop name (mapping recorded instead); no work items filed (pure parity lane, the second lane to
close clean); no new lane-6 parcels beyond the design-tree/decision-tree equivalence note.

## Coverage index and consolidation

Owned by lane 6 ([#2904](https://github.com/melodic-software/claude-code-plugins/issues/2904)):
the per-lesson coverage index mapping every claim to its disposition, dictionary-term adoption,
and final consolidation of this document.
