# ladder-climb-roadmap — PLAN

## Brief

Interview complete (25/25 resolved, verification-backed — ledger committed alongside this plan:
[`interview-checklist.md`](interview-checklist.md)).

Standards grounding: repo `CLAUDE.md` (fresh-docs mandate — desktop-scheduled-tasks doc fetched
2026-07-21; branching/PR conventions). CI-workflow and ruleset surfaces are grounded at Phase II
start against `melodic-software/standards` + ci-workflows conventions (deferred to the phase that
touches them; this document itself is docs-only).

### TLDR

- Climb the Boris ladder 2→3→4 for this org's fleet, snowball-first: build what compounds
  (routines, evidence drains, enforcement rails, quality nets) before linear backlog burn.
- Phase I is ignition (#778): the first standing routine + C2-promotion evidence drain on the
  proving ground — the single unlock every delivered contract waits on.
- Enforcement (#509, ruled + ADR 0002 addendum) and trust accumulation then run as rails under
  everything that follows; 3→4 items stay trigger-gated (runner T4, cost enforcement).

### Goal

The delivered WP1–7 contracts become a LIVE closed loop: Claude kicks off Claude on a schedule,
every completion emits predicate-grade evidence, security-pass execution is machine-enforced on
every PR, and trust promotions (C2 auto-merge eligibility, C3 review blocking, #476 tier
enablement) fire from recorded evidence — human-ratified, never calendar- or discretion-based.
End-state of this roadmap: step 3 operating ("maintenance runs continuously in the background"),
step 4 triggers armed.

### Constraints

- Concept/implementation separation (ratified 2026-07-21): Boris CONCEPTS stay agnostic and
  portable in contracts and setup; machine/repo/user/org specifics live only in bindings —
  the autonomy contract-vs-org-binding shape is the template for every roadmap item.
- Snowball criterion (ratified): compounding builds outrank linear burn in every pick-order.
- No step-skipping: promotions fire on recorded evidence, human-ratified (playbook trap:
  "scaling agent count before the loop has earned widespread trust").
- Enforcement is operator-mandate + consensus practice (OpenSSF/GitHub/NIST), additive to the
  playbook — attribution seams stay explicit (PR #784 pattern).
- #440 outward-write posture: report-only-compatible evidence (check runs, local records).
- Windows: no native sandbox; WSL2/container for step-3 sandboxing work.
- Native-first scheduling (operator amendment on #778): prefer Claude Code's own scheduled-task
  surfaces over hand-managed OS tasks unless the native path can't be easily managed; re-verify
  the scheduling option landscape against current CC docs at each build touchpoint.
- Ownership seams: ruleset→github-iac, reusable workflows→ci-workflows, sync-manifest managed
  files→standards (never edit downstream).
- 7/26 freeze/retro + Mon 7/27 back-at-work: Phases I–II demonstrable by then. Demonstrable
  bar (7/26) ≠ acceptance bar: demonstrable = ≥1 scheduled (non-manual) fire + ≥1 complete
  evidence row joined; the ≥1-week zero-manual-kicks acceptance window necessarily completes
  after the freeze.

### Acceptance criteria (roadmap-level)

- A standing routine fires on schedule with zero manual kicks for ≥1 week; each run's evidence
  row joins in DuckDB (work-class, gate outcome, merge/revert, attestation).
- Security-pass execution is a required check on the plugins repo; every PR carries a verdict
  (real or not-applicable); zero wedged PRs.
- The C2 predicate is COMPUTABLE from accumulated evidence (regardless of whether the flip is
  ratified yet).
- Every promotion that fires cites its evidence window in a reviewed change.

### Captured assumptions

- Native Desktop scheduled tasks work on this machine — app installed and doc-current as of
  2026-07-21 (desktop-scheduled-tasks doc fetched; `~/.claude/scheduled-tasks/` created on
  first task); final proof is the Phase I smoke run.
- claude-code-action credential caveat stands on upstream issue only (verified-by-issue-not-docs).

### Out of scope

- Runner build, L3 backend, cost enforcement, org/multi-team enablement (trigger-gated,
  USER-RESERVED births — triggers recorded in autonomy README + guardrail contracts).
- Universal/org-agnostic packaging beyond what falls out naturally (deferred: day-job trigger).

### Deferred questions

- #778 implementation details (auth/model/window/failure/budget) — arbiter: #778 plan,
  USER-RESERVED (cost decisions); put to the operator at this plan's approval gate.
- #440 tier-scoped write default — arbiter: #440 (design input posted).
- Context-pull leg (#779) — day-job trigger.

## Plan

Roadmap-level plan: five phases, snowball-ordered. Phase I is promoted to its own sub-topic
(`docs/topics/autonomy-ignition/`) — it carries its own exploration, >5 work items, and an
independent commit boundary on the proving ground. Phases III–V are gated on Phase I evidence
and stay [TODO] outlines here until their gates arm; each gets its own sub-topic plan when it
ignites (search-before-create against open issues first).

### Phase I: Ignition (#778) — standing routine + evidence drain [TODO]

Sub-topic: `docs/topics/autonomy-ignition/PLAN.md` (authored at Phase I start, inherits the
interview rulings as design record). Scope, ruled: hourly C2 drain on
`kyle-sexton/autonomy-demo-scratch` via native Desktop scheduled task (fallback: OS scheduler +
`claude -p`, adopted deliberately only if the native surface fails its smoke test); evidence
drain = `signal.work_class` stamp + deterministic-gate outcomes + PR-flow merge/revert events
folded into the proven DuckDB three-source join; demo items move to PR-flow; visibility
surfaces per interview Q8 (GitHub artifacts, telemetry scoreboard, scheduler run history,
optional desktop notification); unattended posture includes the #495 work-items loop-start
permission preflight.

Unattended-execution design surfaces the sub-topic plan MUST cover (fresh-context review
2026-07-21):

- **Machine availability**: Desktop tasks run only while the app is open and the machine is
  awake (doc-verified 2026-07-21). Work items: app autostart on login, power/keep-awake
  configuration (operator choice), reboot/Windows-update survival, missed-fire detection.
- **Catch-up + overlap**: natively bounded — exactly one catch-up run for the most recent
  missed time (older discarded), and an in-progress run causes the next fire to be SKIPPED
  (both doc-verified 2026-07-21). Residual design work: prompt guardrails for stale-time
  catch-up runs, and drain idempotency (claim discipline on the dispatch seam so a catch-up +
  manual run can never double-drain an item).
- **Partial-run reconciliation**: `dontAsk` denies out-of-allowlist calls mid-run — plan for
  branch-without-PR, PR-without-evidence-row, claimed-but-not-drained states: named retry /
  orphan-cleanup / reconciliation items, not a single "failure handling" tap.
- **Spend bounding**: verify the enforcement MECHANISM at build (max-turns / budget flag /
  wrapper kill on `claude -p`; native task model+permission pickers) — a cap that exists only
  as a number in a doc does not bound anything. Cost-enforcement hard caps stay Phase V;
  Phase I needs a working per-run bound.
- **Evidence-write serialization**: DuckDB is single-writer — state the append/lock strategy
  for hourly unattended writes vs interactive queries in the sub-topic plan.

Implementation decisions (auth path, model per run, schedule window, failure-handling posture,
budget cap) are USER-RESERVED — resolved at this plan's approval gate, recorded in the
sub-topic plan.

**Sanity Check:** (binding-specific — these checks pin the ratified proving-ground machine,
`demo-local-session`; they move with the binding, not the concept)
- `ls ~/.claude/scheduled-tasks/` lists the drain task's folder and its `SKILL.md` names the
  drain routine (native path), OR the documented fallback scheduler entry exists
  (`schtasks /query` match) with the fallback decision recorded in the sub-topic plan.
- Run history shows ≥1 scheduled (non-manual) fire — native surface: task detail page run
  history; mechanical fallback: ≥1 session folder under the task's data dir with no manual
  session initiating it (exact probe recorded in the sub-topic plan at task creation).
- Evidence completeness: count(runs fired) == count(evidence rows joined) over the smoke
  window — the canonical join query lives in the sub-topic plan as a runnable stub; a fired
  run with a missing row is a Phase I failure, not noise.
- 7/26 demonstrable bar: ≥1 scheduled fire + ≥1 complete evidence row (work-class stamp AND
  gate outcome AND merge/revert field populated).

### Phase II: Enforcement rail (#509 implementation) [TODO]

ADR-0002-guarded ordering, three repos, ownership seams respected:
0. Pre-flight consumer check (FIRST work item): enumerate every consumer of the ci-workflows
   reusable security workflow before reshaping it — org-wide
   `gh search code --owner melodic-software "uses: melodic-software/ci-workflows"` sweep;
   document each caller's path-filter posture. Also capture the exact reported check context
   name BEFORE any restructure (caller/job layout changes can rename the check; the github-iac
   ruleset must cite the exact context or step 3 wedges every PR).
1. claude-code-plugins: move the security-pass path filter from workflow level to job level so
   every PR reports a verdict (real or not-applicable) — the always-report caller shape.
2. ci-workflows: reusable workflow always-report shape (job-level conditional, never
   workflow-level path filter; add `merge_group` trigger if a merge queue is ever enabled —
   REVISIT-TRIGGER from interview Q3).
3. github-iac: ruleset change making the EXECUTION check required on the plugins repo
   (VERDICT stays earned-advisory per #377 knob floors) — user-approval gate before this PR
   opens; check context name from step 0 verified unchanged post-restructure.

**Sanity Check:**
- Step 0: consumer inventory + captured check context name recorded in the Phase II PR body.
- Step 1: `gh pr checks` on a docs-only test PR in claude-code-plugins shows the security-pass
  check reporting Success with a not-applicable verdict (not Pending, not absent).
- Step 2: grep of the reusable workflow shows a job-level `if:` conditional and NO
  workflow-level `paths:` filter on the security job's trigger.
- Step 3: `gh api repos/melodic-software/claude-code-plugins/rules/branches/main` lists the
  EXECUTION check (exact step-0 context name) in `required_status_checks`.
- Zero wedged PRs: no open PR blocked >24h on a Pending security-pass check
  (`gh pr list` + checks sweep).

### Phase III: Trust accumulation + promotions [TODO — gated on Phase I evidence]

Drain runs accumulate; predicates make cells ELIGIBLE; operator ratifies flips (C2 auto-merge;
C3 Layer-2 blocking; #476 tier per its bot-review precision precondition). Attestation loop
live (scratch#4 pattern). No build until the C2 predicate query returns a non-empty evidence
window.

**Sanity Check:** the C2 predicate is computable — a recorded DuckDB query over accumulated
evidence returns the predicate inputs (merge count, human-revert count, gate pass rate) for a
stated window; each ratified flip cites that window in a reviewed change (PR link on the flip).

### Phase IV: Step-3 guardrail completion [TODO — gated on Phase I demonstrable]

Sandboxing adoption (WSL2/containerized — no native Windows sandbox), token-use policy
(model-selection/advisor discipline), #304 fresh-eyes trust-loop hardening, #530/#534 quality
nets as they surface. Each item gets its own sub-topic or issue-level plan; this phase is a
gate-keeper list, not a single build.

**Sanity Check:** per-item at its own plan; roadmap-level check =
`gh issue list --state open --search "sandboxing OR token-use OR fresh-eyes"` — every Phase IV
item returned carries either a sub-topic plan link or a recorded deferral trigger in its body
or comments (Read each hit; zero unannotated items).

### Phase V: 3→4 (trigger-gated, USER-RESERVED births) [TODO — armed, not planned]

T4 runner build (C2 promotion + clean drain or executor wall), cost enforcement (hard caps),
domain-specific scaled automations, L3 backend (first C5), merge serialization (observed
collisions). Not planned here — each birth is a USER-RESERVED decision whose trigger is
recorded in the autonomy README + guardrail contracts.

**Sanity Check:** trigger registry exists — grep the autonomy README + guardrail matrix hub
for each Phase V item name (runner, cost enforcement, L3 backend, merge serialization); every
hit pairs with a recorded trigger; `gh pr list --search "runner OR cost-enforcement"` returns
no implementation PR whose body fails to cite its trigger's evidence.

### Standing lanes (not phases — run in parallel throughout)

A1/A2 burn as fodder (#627 gauge, 7/26 north star, disk-hygiene #380–382 promoted);
github-plugin lane finishes phases 6–7 under its coordination note; babysit/triage/work loops
per contracts; standards→plugins sync watch (F2 materialization → close #389); dependabot
alert #1 (brace-expansion).

## Blast radius

LOW for this document (docs-only commit on a task branch; every ordering and ruling it encodes
was operator-ratified through the 25/25 interview). The work it SCHEDULES is higher-blast —
Phase I runs Claude unattended (permission posture, spend) and Phase II changes merge
enforcement — but each of those lands through its own gated plan (Phase I: USER-RESERVED
decisions at this approval gate + smoke run; Phase II: three reviewed PRs across ownership
seams). Formal stress-test at roadmap level: skipped (LOW, rulings already adversarially
verified by 4 blind agents + 2 audit agents in the interview session); Phase I's sub-topic
plan gets its own devils-advocate pass before the routine goes live — its unattended-execution
posture is the one genuinely new risk surface.

## Stress-test summary

Step 3 fresh-context plan-review (2026-07-21, blind sub-agent): 3 CRITICAL / 7 IMPORTANT /
4 SUGGESTION. All findings verified against the fetched desktop-scheduled-tasks doc and repo
state, then folded in: unattended-execution design surfaces (availability, catch-up/overlap,
partial-run reconciliation, spend-bound mechanism, DuckDB write serialization) now named
Phase I requirements; Q8 visibility surfaces + #495 preflight restored; Phase II gained the
step-0 consumer/check-name pre-flight and a step-2 check; interview ledger committed with the
plan; demonstrable-vs-acceptance bar split. One finding corrected against the doc: catch-up
bursts and overlapping runs are natively bounded (one catch-up max; in-progress run skips the
next fire) — residual risk is stale-time prompts and drain idempotency, carried into Phase I.
Formal roadmap-level `/devils-advocate`: skipped (docs-only, LOW) — Phase I's sub-topic plan
gets its own pass before the routine goes live.

## Execution shape

Roadmap level is inherently sequential at the front: Phase I gates III and IV; Phase II is the
only phase parallel-safe with Phase I (disjoint files, disjoint repos — I touches the proving
ground + scheduled-task surface; II touches CI/ruleset surfaces across three repos).

| Phase | Surface | Basis |
|---|---|---|
| I | Main session orchestrates; Opus builders in worktrees for proving-ground code (STANDING ORCHESTRATION CONTRACT) | Judgment-heavy setup + machine-local surfaces (Desktop app) only the main session can probe |
| II | Sequential PR chain, one repo at a time, main session + builder per repo | ADR ordering guard: caller restructure → always-report shape → required check |
| III–V | Not routed — gated; routed when their sub-topic plans ignite | Gates not yet armed |

Wave shape: Phase I first (ignition is the unlock and the 7/26 demonstrable); Phase II may
interleave once Phase I's routine definition is live and babysitting. Parallel cost: one
builder agent per active phase, worktree-isolated; sequential fallback = finish Phase I before
any Phase II PR (fallback trigger: scope-fence violation or main-session babysit overload).

## Open questions

- The five #778 USER-RESERVED decisions (auth, model, window, failure handling, budget) — put
  to the operator at this plan's approval gate; recorded in the sub-topic plan once answered.

## Handoff to implementation

### User-approval gates

- This roadmap PLAN itself (approve / modify / reject).
- The five #778 implementation decisions (USER-RESERVED — cost/spend).
- Phase II step 3 (github-iac required-check flip) — confirm before the ruleset PR opens.
- Any Phase III promotion flip (operator ratification, per constraint).
- Phase V births (USER-RESERVED, trigger-cited).

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Phase I promoted to sub-topic `docs/topics/autonomy-ignition/` with its own
  PLAN.md; roadmap phases III–V stay outlines here until gated ignition.
- [EXEC-SHAPE] Phase I/II interleave permitted after Phase I routine is live; sequential
  fallback documented above.
- [EXEC-SHAPE] Builders per STANDING ORCHESTRATION CONTRACT: Fable plans, Opus builders in
  worktrees, agents never touch git, main thread verifies empirically before every commit,
  fetch-first, babysit 15-min quiet grace, counts from the tree.
- [EXEC-SHAPE] Interview ledger committed into this topic dir (review finding: the rulings'
  audit trail must survive `.work` sweeps) — supersedes the draft's memory-slice-only
  disposition.
- [EXEC-SHAPE] 7/26 demonstrable bar defined as ≥1 scheduled fire + ≥1 complete evidence row
  (review finding: demonstrable ≠ acceptance; the ≥1-week window outlives the freeze).
- [FALLBACK — confirm or override] Scout finding: the routines contract binds SIX adapter
  obligations (trigger-dispatch.md:45), while #778's body says "seven obligations" — treated
  as issue-text drift, six is authoritative; correct #778 or override here.

### Mechanical work

- Commit this PLAN.md on `docs/ladder-climb-roadmap`; PR titled
  `docs(roadmap): commit ladder-climb-roadmap plan (interview-ratified)`; squash merge.
- Commit `interview-checklist.md` (scrubbed) alongside this plan — the rulings' audit trail
  must survive `.work` hygiene sweeps and be visible to fresh sessions.
- Delete `.work/ladder-climb-roadmap/PLAN-draft.md` locally (memory slice, gitignored —
  superseded by this file).
- Phase tags advance `[TODO]`→`[DOING]`→`[DONE]` as phases move; mid-flight pivots append
  dated scope-change notes, never rewrite.
