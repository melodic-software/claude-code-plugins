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

1. **Compose the brief** — an explicit scope fence (ALLOWED files/actions and FORBIDDEN files/actions, enumerated), a divergence-escalation clause (verbatim in every brief: "if an assumption in this brief proves wrong or the task requires touching anything FORBIDDEN, STOP and report — do not improvise"), the project invariants the task touches (from the consuming project's `CLAUDE.md` / rules), the phase's acceptance criteria, and any model routing the plan specifies. **When the worker edits in a dedicated worktree** (an out-of-tree sibling or any checkout other than the session's default), the brief MUST also give that worktree's absolute path and instruct the worker to never rely on the shell's working directory persisting across separate tool calls — anchor every command that touches the worktree — file edits AND git operations (`status`, `add`, `commit`, `diff`, `log`, everything) — with `git -C <worktree-path>` (or re-`cd` into the path at the start of each call), never a one-time `cd`, since cwd can drift between a read and the next write and silently risks committing into the wrong checkout. The brief MUST also front-load three CI-hygiene clauses: no issue-number back-references in code comments (the `comment-hygiene` check flags them; `TODO(#issue)` is the sanctioned exception); any new regular file with a shebang (never a `120000` symlink — `git update-index --chmod=+x` fails on one) must be marked executable on both the worktree and the index in this order: `chmod +x <path>`, then `git add <path>` to stage it (a not-yet-tracked path fails `git update-index --chmod=+x` outright — "cannot add to the index" — so the first-time stage MUST happen before the mode override), then `git update-index --chmod=+x <path>` to force the index mode explicitly since a plain `git add` alone can't be trusted to carry an executable bit across every platform/filesystem (the `exec-bit` check flags a tracked shebang file recorded non-executable); and commit and push as early as practical — before the CI-poll tail — so a mid-flight worker session-limit death never orphans unpushed work; this early commit is a source-only checkpoint, not a substitute for the phase-boundary plan-mark commit, which the orchestrator still runs separately (see Phase boundaries below). PR creation stays out of the brief: it belongs to the orchestrator's post-verification flow (`/implementation:implement` Step 5), invoked only after every worker return is verified and the phase's build/test gate passes
2. **Dispatch** the worker
3. **Verify the return against direct evidence before accepting edits** — worker returns are synthesis, not ground truth; promote their claims to direct evidence (diff read, grep, file Read) before building on them
4. **Build/test main-side** — invoke `/toolchain:check` from the main window when the `toolchain` plugin is installed, otherwise run the project's own build/test command main-side; never accept a worker's green claim as the build signal
5. **Route worker divergence reports into `/implementation:implement` "Step 3: Divergence Detection"** — a worker STOPping per the divergence-escalation clause is a divergence signal, severity-assessed the same way; the orchestrator revises the brief or routes back to the planning skill (`/planning:plan review` when installed)

## Divergence in non-interactive runs

In a session with no human to escalate to, stop-and-escalate on Moderate divergence deadlocks the run. There: pick the CONSERVATIVE option — the one truest to the plan's intent with the smallest blast radius — log it to a `DEVIATIONS.md` beside the plan artifact at deviation time (what was planned, what was done instead, why, blast radius), and keep going; the deviation log is the escalation, reviewed at PR time. Major divergence (fundamental assumption wrong) still STOPS even autonomously — park the run with a handoff note rather than improvising a new design. Interactive sessions keep the `/implementation:implement` "Step 3: Divergence Detection" escalation ladder unchanged.

## Phase boundaries

**Ritual unchanged, except the phase-boundary commit's contents.** Every phase boundary runs the `/implementation:implement` "Step 4: Task Tracking and Phase-Boundary Handoff" ritual — plan marks, handoff entry, status summary, mark-then-commit, resume prompt — with one scoped exception: Step 4 item 4 normally combines a phase's source changes and its plan-mark in one commit, but a dispatched worker already committed and pushed its source early (per the push-early clause above) before the orchestrator's acceptance-criteria verdict exists to mark the phase `[DONE]`. In that case the phase-boundary commit is plan-marks-only — the worker's earlier commit already carries the source — rather than the combined single commit inline mode produces. Orchestration changes who edits and when the source lands, not whether progress gets recorded.

**Fresh-context verifier before marking a phase `[DONE]`:** the Step 4 ritual's acceptance-criteria verdict (item 1) is, in orchestrated runs, *dispatched* rather than rendered inline — send a separate verifier subagent to check the phase's acceptance criteria against the actual diff, handed binary criteria and the diff with your rationale withheld. Where the phase's outcome is high-stakes and correlated blind spots are the risk, prefer a cross-vendor advisor for that verifier **when one is installed** — e.g. the OpenAI Codex plugin's `/codex:review --wait` or `/codex:adversarial-review --wait` — with the fresh-context same-vendor verifier sub-agent as the stated fallback, never a route to a command that may not resolve. It applies in every mode: autonomous runs MUST; interactive runs MUST for any phase beyond a mechanical, behavior-preserving change. Surface subagent results in the response before ending the turn.

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
| Worker divergence report | Severity-assess per `/implementation:implement` "Step 3: Divergence Detection"; Major → the planning skill (`/planning:plan review` when installed) |
| Every worker return | Verify against direct evidence, then `/toolchain:check` main-side (when the `toolchain` plugin is installed; else the project's own build) |
| Phase sanity check passes | `/implementation:implement` "Step 4" ritual (its item-1 verifier gate applies in every mode; orchestrated runs dispatch it — see Phase boundaries) |
| All phases complete | `/implementation:implement` "Step 5: Completion and Handoff" |

## What this skill does NOT do

- **Does not edit inline** — inline execution cadence, commit discipline, and mode context files (feature/bugfix/refactor) are `/implementation:implement`'s
- **Does not create or revise plans** — a planning pass produces plans; this skill executes routing tables
- **Does not replace `/toolchain:check`** — the `toolchain` plugin's check skill (when installed) is the SSOT; this skill invokes it main-side at the right moments, falling back to the project's own build command when that plugin is absent

## Gotchas

- **Never accept a worker's green claim as the build signal.** Workers report synthesis; the main window runs `/toolchain:check` (or the project's own build when the `toolchain` plugin is absent) itself after every accepted return
- **A worker STOP is a divergence signal, not a failure.** Route it through the `/implementation:implement` Step 3 severity ladder; revising the brief is the cheap fix, a plan review the escalation
- **Surface subagent results before ending the turn.** Results left unsurfaced at turn end are lost to the user
- **A worker's worktree cwd does not persist across tool calls.** Brief every dedicated-worktree worker to anchor every command — edits AND git status/add/commit/diff/log — with `git -C <worktree-path>` or a re-`cd` per call, never a one-time `cd`
- **No issue-number back-references in code comments.** Brief every worker that a comment citing an issue number (`# Issue #NNN ...`, `(issue #NNN obs #N)`) trips the `comment-hygiene` check; `TODO(#issue)` is the sanctioned exception
- **New shebang files need `chmod`, then `git add`, then `git update-index --chmod=+x` — in that order.** Brief every worker: `chmod +x <path>`, then `git add <path>` (a not-yet-tracked file fails `git update-index --chmod=+x` outright — it can't override the index mode of a path that isn't staged yet), then `git update-index --chmod=+x <path>` to force the index mode explicitly (skip symlinks — staged `120000`, they fail the same command) — a shebang file staged non-executable trips the `exec-bit` check
- **Push early, before the CI-poll tail — but never the PR.** Brief every worker to commit and push as early as practical rather than deferring until its fix-and-verify loop is done, so a mid-session death never orphans unpushed work. This is a source-only checkpoint commit — the phase-boundary plan-mark commit (Step 4) still runs separately, orchestrator-side, once the phase's acceptance criteria are verified. PR creation stays out of every worker brief — it happens in the orchestrator's post-verification flow (`/implementation:implement` Step 5) after every return is verified and the build/test gate passes
- **Scope-fence drift applies to agent returns.** Every worker return is a decision boundary — classify proposed follow-ups per `/implementation:implement` "Step 3.5: Scope-fence drift detector (run at every decision boundary)" before announcing them
