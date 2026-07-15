---
name: implement-dispatch
description: "Orchestrate worker subagents to execute an approved plan — the main window composes scope-fenced briefs, dispatches workers, verifies their returns against direct evidence, and builds main-side instead of editing inline. Use when the plan routes phases to worker surfaces or the session runs autonomously; for interactive all-inline execution use /implementation:implement instead."
argument-hint: "[phase] (e.g., /implementation:implement-dispatch, /implementation:implement-dispatch phase-2)"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Structural variant of `/implementation:implement` for orchestrated execution: the main window orchestrates instead of editing. Same stage, same plan, different execution mechanism — `/implementation:implement` edits inline; this skill dispatches scope-fenced workers and verifies their returns.

## When this skill applies (vs `/implementation:implement`)

**Orchestration mode detection** — infer autonomous vs interactive from the session shape: a goal/loop harness driving turns with no human in the cycle, a plan that declares itself autonomous-ready, or an explicit orchestration instruction means **autonomous**; a human reviewing each turn means **interactive**.

**Autonomous:** the main window is orchestrator only — MUST dispatch workers per phase; orchestrated cadence is the **default** even when the plan's routing is all-main-window (synthesize per-phase worker rows from the plan). Cap concurrent dispatch waves at 3–5 workers.

**Interactive:** read the plan's execution-shape/routing table. Worker rows present (any surface other than main-window) → this skill's dispatch cadence for those phases. Routing table absent or all main-window → `/implementation:implement` classic inline cadence instead.

`/implementation:implement` shares this detection at its Step 0 and chains here; invoking this skill directly with a worker-routed plan is equivalent.

## Arguments

`$ARGUMENTS` — optional phase selector (e.g. `phase-2`). When a phase is named, scope the dispatch cadence to that plan phase only. Otherwise walk the remaining plan phases strictly in order — never dispatch a later worker-routed phase past an incomplete earlier phase: dispatch each worker-routed phase as it becomes current; in interactive mode, at the first inline-routed phase hand back to `/implementation:implement` classic cadence and re-enter here when a later worker-routed phase becomes current. Under autonomous mode every remaining phase dispatches in order, synthesizing worker rows per the Autonomous rule above when the routing table lacks them.

## Prerequisites (before any dispatch)

Run the `/implementation:implement` "Step 1: Prerequisite Check" preflight first — approved plan present, branch correct (never the default branch), no unrelated dirty-tree changes. Chaining in from `/implementation:implement` Step 0 arrives with this already done; a DIRECT invocation of this skill must run it before composing the first brief.

## Dispatch cadence (per worker-routed phase)

1. **Compose the brief** — an explicit scope fence (ALLOWED files/actions and FORBIDDEN files/actions, enumerated), a divergence-escalation clause (verbatim in every brief: "if an assumption in this brief proves wrong or the task requires touching anything FORBIDDEN, STOP and report — do not improvise"), the project invariants the task touches (from the consuming project's `CLAUDE.md` / rules), the phase's acceptance criteria, and any model routing the plan specifies
2. **Dispatch** the worker
3. **Verify the return against direct evidence before accepting edits** — worker returns are synthesis, not ground truth; promote their claims to direct evidence (diff read, grep, file Read) before building on them
4. **Build/test main-side** — invoke `/toolchain:build` from the main window when the `toolchain` plugin is installed, otherwise run the project's own build/test command main-side; never accept a worker's green claim as the build signal
5. **Route worker divergence reports into `/implementation:implement` "Step 3: Divergence Detection"** — a worker STOPping per the divergence-escalation clause is a divergence signal, severity-assessed the same way; the orchestrator revises the brief or routes back to the planning skill (`/planning:architect review` when installed)

## Divergence in non-interactive runs

In a session with no human to escalate to, stop-and-escalate on Moderate divergence deadlocks the run. There: pick the CONSERVATIVE option — the one truest to the plan's intent with the smallest blast radius — log it to a `DEVIATIONS.md` beside the plan artifact at deviation time (what was planned, what was done instead, why, blast radius), and keep going; the deviation log is the escalation, reviewed at PR time. Major divergence (fundamental assumption wrong) still STOPS even autonomously — park the run with a handoff note rather than improvising a new design. Interactive sessions keep the `/implementation:implement` "Step 3: Divergence Detection" escalation ladder unchanged.

## Phase boundaries

**Ritual unchanged.** Every phase boundary runs the `/implementation:implement` "Step 4: Task Tracking and Phase-Boundary Handoff" ritual in full — plan marks, handoff entry, status summary, mark-then-commit, resume prompt. Orchestration changes who edits, not how progress is recorded.

**Fresh-context verifier before marking a phase `[DONE]`:** the Step 4 ritual's acceptance-criteria verdict (item 1) is, in orchestrated runs, *dispatched* rather than rendered inline — send a separate verifier subagent to check the phase's acceptance criteria against the actual diff, handed binary criteria and the diff with your rationale withheld. It applies in every mode: autonomous runs MUST; interactive runs MUST for any phase beyond a mechanical, behavior-preserving change. Surface subagent results in the response before ending the turn.

### Resident-vs-clear at phase boundaries

The orchestrator may stay resident across phase boundaries instead of clearing context per phase. Stay resident only when ALL of:

- **(a) Context headroom** — main-window context is comfortably below the compaction zone, evidenced by actual context stats captured this turn — never conversation-length vibes
- **(b) Next phase is also worker-routed** per the routing table (an inline-routed next phase wants a fresh window for its own reads)
- **(c) No model/domain switch pending** for the next phase

Any criterion fails → clear + resume from the emitted prompt. **The phase-boundary ritual and resume-prompt emission are UNCHANGED either way** — resident mode still marks DONE, writes the handoff, and emits the prompt (the prompt is crash insurance, not only a clear-context artifact).

## Integration with workflow

| Condition | Action |
|-----------|--------|
| Phase is inline-routed (main-window), interactive mode | Hand back to `/implementation:implement` classic cadence |
| Phase is inline-routed or routing table absent, autonomous mode | Synthesize a worker row and dispatch — the orchestrator never does volume edits |
| Worker divergence report | Severity-assess per `/implementation:implement` "Step 3: Divergence Detection"; Major → the planning skill (`/planning:architect review` when installed) |
| Every worker return | Verify against direct evidence, then `/toolchain:build` main-side (when the `toolchain` plugin is installed; else the project's own build) |
| Phase sanity check passes | `/implementation:implement` "Step 4" ritual (its item-1 verifier gate applies in every mode; orchestrated runs dispatch it — see Phase boundaries) |
| All phases complete | `/implementation:implement` "Step 5: Completion and Handoff" |

## What this skill does NOT do

- **Does not edit inline** — inline execution cadence, commit discipline, and mode context files (feature/bugfix/refactor) are `/implementation:implement`'s
- **Does not create or revise plans** — a planning pass produces plans; this skill executes routing tables
- **Does not replace `/toolchain:build`** — the `toolchain` plugin's build skill (when installed) is the SSOT; this skill invokes it main-side at the right moments, falling back to the project's own build command when that plugin is absent

## Gotchas

- **Never accept a worker's green claim as the build signal.** Workers report synthesis; the main window runs `/toolchain:build` (or the project's own build when the `toolchain` plugin is absent) itself after every accepted return
- **A worker STOP is a divergence signal, not a failure.** Route it through the `/implementation:implement` Step 3 severity ladder; revising the brief is the cheap fix, a plan review the escalation
- **Surface subagent results before ending the turn.** Results left unsurfaced at turn end are lost to the user
- **Scope-fence drift applies to agent returns.** Every worker return is a decision boundary — classify proposed follow-ups per `/implementation:implement` "Step 3.5: Scope-fence drift detector (run at every decision boundary)" before announcing them
