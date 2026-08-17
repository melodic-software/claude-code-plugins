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

## Lanes 3 through 5

Rows land here as each lane closes: compaction doctrine (#2901), plan mode (#2902), and
interview parity (#2903).

## Coverage index and consolidation

Owned by lane 6 ([#2904](https://github.com/melodic-software/claude-code-plugins/issues/2904)):
the per-lesson coverage index mapping every claim to its disposition, dictionary-term adoption,
and final consolidation of this document.
