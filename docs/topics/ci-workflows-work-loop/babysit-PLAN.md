# babysit-loop (source-control lane) — Brief (partial)

Authored by the BABYSIT session, now terminated. SUCCESSION: the
work-loop session owns this track — absorb the alignment notes,
drive the open questions to decisions with the operator (done:
Q13–Q15 + HITL probe locked below; the interim
`babysit-open-questions.md` was folded in and deleted), finalize
this Brief, and carry it into planning alongside the work-loop
Brief. Ledger with all grounding facts:
`babysit-interview-checklist.md` (same dir). The babysit skill build
(`/source-control:babysit-loop`) then proceeds wherever the operator
runs it; nothing else lives only in the dead session.

## Brief

**TLDR**: Reusable `/source-control:babysit-loop <owner/repo> [flags]`
skill in the source-control plugin — the babysit lane of the
3-session topology. Wraps `/source-control:babysit-prs` in a
standing/drain loop with configurable autonomy dimensions;
ci-workflows (drain mode, autopilot) is the first instantiation.

### Goal

1. New skill `/source-control:babysit-loop` in the source-control
   plugin (`melodic-software/claude-code-plugins`): loop layer over
   babysit-prs — stop conditions, self-paced cadence with idle
   backoff, cycle-budget restart semantics, lane telemetry, subagent
   discipline preamble, autonomy-dimension configuration.
2. Shared cross-plugin loop-lane convention (see Placement below).
3. ci-workflows instantiation: `--drain` autopilot loop scoped to
   `melodic-software/ci-workflows`.

### Decisions locked (babysit interview Q1–Q12)

- Tier for ci-workflows: **autopilot** (only open PRs are
  bot-authored; safe/worker find zero). Draft elevation + barrier
  clearing in scope; fable subagents for conflicts/blockers; every
  subagent runs /re-anchor:sweep-all-disciplines +
  /re-anchor:use-your-skills + /re-anchor:do-your-research.
- Scope: repo-only per invocation (repo is the skill's required arg).
- do-not-merge label: respected by default; strip only behind
  explicit override flag.
- Stop modes: default **standing** (idle backs off toward 1h
  wakeups; no activity-timeout stop); `--drain` stops at 0 open PRs
  AND 0 open issues. ci-workflows uses `--drain`.
- Pacing: dynamic self-paced /loop (matches work-loop Q1).
- Sequencing: build skill first, then launch the lane through it.
- Concurrency safety (3-session topology): activity grace window
  (default 30 min) — never elevate/resolve/merge a PR whose head
  moved or received comments inside the window; never elevate a
  draft carrying a WIP signal (title marker, do-not-merge label,
  non-green checks). Existing babysit-prs yield-on-head-move +
  foreign_activity discipline retained.
- Cycle budget: adopt #691 resolution (a) — budget restarts the
  SESSION, never ends the LOOP.
- Telemetry: lane edits its one #502-style status comment per cycle
  (convention material, see Placement).

### Decisions locked (rounds Q13–Q15 + probe, operator-confirmed 2026-07-23)

- Q13 config model: tier presets + per-dimension overrides. Interactive session with
  ambiguous/absent config → AskUserQuestion mini-interview, then offer to persist. Headless
  launch never blocks: resolved config (args or persisted) or tier defaults + logged notice.
- Q14 persistence: new keys on the layered `source-control.md` seam (user-global → repo tracked →
  local overlay; per-key merge per `reference/config-resolution.md`); invocation args win. Both
  loop lanes cite the same consumer-config-layering registry row.
- Q15 autonomy-dimension contract: dimensions 1–7 (discovery scope, fixing, thread resolution,
  draft elevation, barrier overrides, merge, escalation) + always-on safety knobs (grace window,
  yield-on-head-move, no-monitor clause, watched-owner boundary) + loop knobs (standing vs drain,
  #691 cycle budget, #502 telemetry). Tiers = named presets over the dimensions. Per-bot
  allowlists / per-check policies deferred post-V1.
- HITL escalation (dimension 7 default): reuse the loop-lane escalation contract — tracker item
  with `needs-human` role label + machine-marked comment (HITL session polls that surface);
  telemetry remains the report channel, never the sole escalation path when human action is
  required.

### Placement finding — RECONCILED (work-loop session, 2026-07-23)

Work-loop session AGREES: shared concerns move to `docs/conventions/loop-lane/` + registry row;
work-loop Brief goal 1b now owns that deliverable; the in-plugin reference-doc plan is retracted.
Alignment notes below are absorbed into the work-loop Brief. Remaining open here: Q13–Q15 + HITL
probe (put to operator as work-loop interview round 6).

### Original finding (babysit session)

`docs/PLUGIN-PHILOSOPHY.md`: sibling-plugin file imports are
defects; "a new cross-plugin convention lands in an owner doc
before a second plugin adopts it" (convention registry,
`docs/conventions/<concern>/`).

Work-loop Brief currently puts the shared reference doc (escalation
contract, 3-session topology, model-routing capability tiers) INSIDE
the work-items plugin. The babysit lane lives in source-control and
cannot read work-items files — the moment source-control adopts the
topology/escalation/tier language, those concerns are cross-plugin
and must move to a repo-level convention owner doc (e.g.
`docs/conventions/loop-lane/`) with a registry row. Proposed split:

- `docs/conventions/loop-lane/` — 3-session topology, escalation
  contract, capability tiers (IDs live-resolved), loop-layer
  invariants: stop shapes, cycle-budget/#691 semantics, idle
  backoff, #502 telemetry comment, headless-config floor, subagent
  discipline preamble.
- work-items keeps only work-lane-specific mechanics; source-control
  keeps only babysit-specific mechanics; both cite the convention.
- autonomy plugin: governing policy pointer (guardrail matrix), not
  a mechanics home. Compatible with runner.md interim-executor
  framing and future #480 consumption.

### Alignment notes for absorption

- Topology tier wording: work-loop Brief says "babysit (worker
  tier) merges". Correct the topology doc to: worker-loop never
  merges; babysit lane owns merges at a merge-capable tier — worker
  minimum, autopilot where bot PRs are in scope (ci-workflows case).
- rate-limit-guard: babysit-loop is a third consumer of the shared
  subscription windows — it must integrate the same guard contract
  (pause new work ≥90%, drain-then-pause). Add source-control lane
  to the guard's consumer list.
- Exit-condition composition: babysit `--drain` (0 PRs AND 0 issues)
  intentionally outlives work-loop's exit (all issues closed or
  PR'd) — babysit finishes merging the tail.
- Model routing: babysit subagent defaults (fable for
  conflict/blocker resolution per operator directive) should be
  expressed in the shared capability-tier vocabulary, not hardcoded
  model names.
- #502 telemetry + #691 cycle-budget semantics absent from work-loop
  Brief — both lanes need them; convention doc is the home.

## Plan

### Standards grounding

Same resolution as the sibling work-loop PLAN (no standards index anywhere; rung 4/6 inference —
see `PLAN.md` "Standards grounding" table; additional surfaces below):

| Surface | Source | Provenance |
|---|---|---|
| Babysit mechanics | `plugins/source-control/skills/babysit-prs/SKILL.md` (tier matrix L98-107, guarded wrappers L185-238, userConfig surface L281-316), `reference/loop.md` (cadence L426-454, HEAD gates L132-176) | team (repo) |
| Config seam | `plugins/source-control/reference/config-resolution.md` (layered `source-control.md`, per-key merge L68-93); `docs/conventions/consumer-config-layering/README.md` (implementers row L203) | team (repo) |

### Dependencies

- Consumes work-loop PLAN Phase 2 (`docs/conventions/loop-lane/` — topology, escalation,
  tiers, stop shapes, #691/#502 semantics, headless-config floor) and Phase 3
  (`rate-limit-guard` reader contract). B1/B2 start after Phase 2 merges; B3 additionally
  after Phase 3 and work-loop Phase 5 (tracker binding, for the escalation surface).
- Grounding fact shaping B1: existing babysit-prs config is NATIVE plugin `userConfig`
  (`${user_config.babysit_*}`, user-settings-scoped) — it cannot express repo-scoped lane
  config (drain vs standing is a property of the target repo). Q14's layered
  `source-control.md` seam is therefore the correct home for LOOP keys; per-user babysit_*
  keys stay where they are. The two surfaces coexist; B1 documents the split.

### Phase B1: loop config keys on the layered seam [TODO]

One PR to claude-code-plugins (may share a branch with B2).

| File | Action | What |
|---|---|---|
| `plugins/source-control/reference/config-resolution.md` | Modify | widen scope statement beyond the commit-subject convention; add loop-lane key table: `babysit_loop_stop_mode` (standing\|drain), `babysit_loop_tier_preset`, per-dimension override keys (dimensions 1–7), `babysit_loop_grace_window_minutes` (default 30), `babysit_loop_cycle_budget`; precedence: invocation args win over all layers, EXCEPT dimension 6 (merge) where an argument may only select a lower rung — merge-rung raises bind only from the tracked seam config, per the loop-lane convention's "Merge-rung raises are seam-only" rule; per-key merge unchanged |
| `docs/conventions/consumer-config-layering/README.md` | Modify | update source-control implementers row: both loop lanes cite the row (Q14) |

Key-name shapes above are working names — final names follow the seam's existing conventions at
build time.

- **Sanity Check:** `grep -ci "stop.mode\|standing\|drain" plugins/source-control/reference/config-resolution.md` ≥ 2 (loop-key table present — concept-level check; literal key names are working names subject to seam conventions).
- **Sanity Check:** `grep -c "loop" docs/conventions/consumer-config-layering/README.md` ≥ 1 (row updated).
- **Sanity Check:** repo CI green.

### Phase B2: `/source-control:babysit-loop` skill [TODO]

Review: architecture
One PR (or same PR as B1). Thin loop layer over `/source-control:babysit-prs` — never restates
its tier matrix, guarded wrappers, or safety discipline; invokes it per cycle with the resolved
tier + scope.

| File | Action | What |
|---|---|---|
| `plugins/source-control/skills/babysit-loop/SKILL.md` | Create | loop layer (content below) |
| `plugins/source-control/skills/babysit-loop/evals/evals.json` | Create | per evals schema |
| `plugins/source-control/CHANGELOG.md` + `.claude-plugin/plugin.json` | Modify | version bump |
| `scripts/skill-leaf-name-registry.txt` | Modify | register `babysit-loop` leaf (gate) |

SKILL.md delta only: required arg `<owner/repo>`; config resolution per B1 (args → layered seam
→ tier defaults; interactive ambiguity → AskUserQuestion mini-interview + offer to persist;
headless never blocks — resolved config or tier defaults + logged notice, per convention
headless-config floor); stop modes (default standing with idle backoff toward 1h wakeups;
`--drain` stops at 0 open PRs AND 0 open issues — intentionally outlives work-loop's exit);
autonomy-dimension contract (dimensions 1–7 + always-on safety knobs + loop knobs; tiers =
named presets; dimension 6 (merge) shipped default = human merge for everything except
gate-proven bot/C2 mechanical PRs, higher rungs opt-in per the autonomy ladder — a
tracked-seam config edit is the recorded human-ratified promotion (work-loop PLAN Phase 2
item 1); per-bot allowlists deferred post-V1); concurrency safety (30-min activity grace
window — never elevate/resolve/merge a PR whose head moved or received comments inside it;
never elevate a draft carrying WIP signals; babysit-prs yield-on-head-move + foreign-activity
discipline retained by citation); #691 (a) + #502 telemetry + escalation (dimension 7 default:
tracker item with `needs-human` role label + machine-marked comment) BY CITATION to
`docs/conventions/loop-lane/`; guard reader-contract integration (third consumer);
do-not-merge respected by default, strip only behind explicit override flag; subagent
discipline preamble + capability-tier vocabulary for conflict/blocker subagents (frontier tier
per operator directive — expressed as tier, never model name); dynamic `/loop` pacing via
ScheduleWakeup within [60,3600]s clamp (cite loop.md cadence table; `/schedule` for daily-scale
cadence).

Cross-cutting work items (reviewer findings, mirrors work-loop Phase 4): inline the guard
operable floor (fixed tee path, 90% threshold, staleness, drain-then-pause) — cite reader
contract for provenance only (installed plugins cannot read sibling-plugin or repo docs at
runtime); `--drain` exit includes the drain-terminal state (0 open PRs AND 0 open issues OR all
remaining open items human-gated → report + clean stop) per the loop-lane convention
`[FALLBACK]` invariant; durable loop state (cycle count, backoff level) persists in the #502
telemetry block; every cross-plugin reference (guard, loop-lane vocabulary) declared-or-guarded
per seam phrasing. Naming: `babysit-loop` is verb-first — passes the grammar rule.

- **Sanity Check:** `/skill-quality:check babysit-loop` PASS.
- **Sanity Check:** `bash scripts/validate-plugins.sh` exit 0.
- **Sanity Check:** `grep -c "conventions/loop-lane" plugins/source-control/skills/babysit-loop/SKILL.md` ≥ 1 and `grep -c "babysit-prs" ...` ≥ 1 (cites both owners).
- **Sanity Check:** `grep -En "claude-(opus|sonnet|haiku|fable)-[0-9]" plugins/source-control/skills/babysit-loop/SKILL.md` returns empty (tier vocabulary only).

### Phase B3: ci-workflows drain instantiation [TODO]

Launch through the skill (sequencing decision: build first, then launch through it):
`/source-control:babysit-loop melodic-software/ci-workflows --drain` at **WORKER tier**
(operator-resolved 2026-07-23, superseding the interview-time autopilot pick: that premise —
"only open PRs are bot-authored" — is invalidated the moment work-loop ships PRs, and the bot
case (standards-sync) is already covered by native armed auto-merge, #213). The lane's
justification is barrier clearing + draft elevation + gate-proven merges of own/bot PRs;
security/posture blockers stay hard escalations. Higher rungs up to full autonomy (frontier
subagents resolving conflicts/comments and driving to merge) are reachable via the
autonomy-ladder config on the tracked seam (work-loop PLAN Phase 2 item 1) — each raise is a
recorded human-ratified flip; merge scope bounded by the matrix reconciliation (C3 → human
merge unless flipped). First cycle observed attended; telemetry comment = per-lane tracking
issue in ci-workflows (operator-resolved).

- **Sanity Check:** first-cycle report shows tier=worker, mode=drain, grace-window active;
  no merge performed on any PR with head activity inside the grace window (report assertion).
- **Sanity Check:** lane telemetry comment exists and is EDITED (not duplicated) on second
  cycle — `gh api` comment count for the marker returns 1.
- **Sanity Check:** drain exit observed or standing correctly backing off (ScheduleWakeup
  delays growing toward 3600s in the report) when queue empty.

## Blast radius

HIGH — autonomous merge authority (autopilot) in an org repo; shares the org-wide loop-lane
convention; config-seam widening touches a cross-plugin registry row. Rides the work-loop
PLAN's formal stress-test (single Step 4 run covers both tracks; findings recorded in both).

## Stress-test summary

Shared Step 3/4 run with the work-loop PLAN (see its "Stress-test summary" for the full
ledger). Babysit-specific outcomes: tier re-opened (B3 — autopilot → recommended worker, Open
Decision 6); merge scope bounded by the autonomy matrix reconciliation (Open Decision 5);
drain exit hardened (snapshot semantics + drain-terminal state + bot-author triage rule make
exit reachable against automated intake); guard floors inlined; `--bg` tee verification gates
any unattended migration.

## Execution shape

| Phase | Surface | Basis |
|---|---|---|
| B1 | main-session | small doc/config PR, judgment on seam wording |
| B2 | main-session (+ fresh-context review sub-agent) | skill authoring, playbook-governed |
| B3 | main-session, operator present first cycle | launch + observation |

Sequential B1 → B2 → B3; parallel-safe with work-loop Phases 3–4 (disjoint plugin dirs) per the
work-loop PLAN execution shape. Scope fence: `plugins/source-control/` +
`docs/conventions/consumer-config-layering/README.md` only.

## Open questions

(none beyond the shared telemetry-home question — work-loop PLAN "Open questions" 1)

## Handoff to implementation

### User-approval gates

- B3 launch is operator-initiated; autopilot tier confirmed per interview but the FIRST cycle
  runs attended.
- Any strip of a do-not-merge label requires the explicit override flag — never default.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] B1+B2 may share one PR/branch (same plugin, one reviewable unit). Evidence:
  plugin norms — config seam + consuming skill land together elsewhere in the plugin's history.
- [EXEC-SHAPE] Working key names in B1 subject to seam naming conventions at build.

### Mechanical work

- Commit convention per repo norms; CI green per PR; fresh-context review before the PR;
  phase tags advanced here as work completes; close-out shared with work-loop PLAN.
