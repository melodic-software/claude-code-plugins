---
name: implement
description: "Execute approved plans, fix bugs, and make code changes inline with incremental validation — TDD by default, build+test after each logical block, commit at green checkpoints, and divergence detection that routes back to planning instead of pushing through a broken approach. Use for 'implement this', 'execute the plan', 'fix this bug', 'refactor', or whenever code is about to be written; modes: feature, fix, refactor, config."
argument-hint: "[task or mode] (e.g., /implementation:implement, /implementation:implement feature, /implementation:implement fix login-bug, /implementation:implement refactor)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`
Recent commits: !`git log --oneline -5 2>/dev/null || echo "no commits"`
Uncommitted changes: !`git diff --stat HEAD 2>/dev/null | tail -1 || echo "none"`

## Purpose

Implementation is where plans become code. This skill structures the execution phase so changes are made incrementally, validated continuously, and abandoned early when the approach isn't working — rather than pushing through a broken implementation and discovering problems at PR time.

It sits between planning and verification: exploration and external research provide understanding, a planning pass produces an approved plan, this skill executes it with discipline, and the companion skills in the separate `testing` and `verification` plugins (`/testing:plan`, `/testing:write`, `/testing:diagnose`, `/verification:confirm`) — no longer siblings of this skill after the plugin split — validate the result when those plugins are installed.

**Philosophy**: cost of a mid-implementation replan is minutes; cost of discovering a flawed approach at PR review is hours. Validate incrementally, commit at checkpoints, and route back to planning the moment something feels wrong.

## Progress tracking

Track skill Steps 0–5 in-session via the task list. Durable progress lives in the plan artifact itself (phase tags, `- [ ]` step boxes) plus the handoff notes written at phase boundaries (Step 4) — do not mirror progress into a second checklist file. Placement resolves per the topic-docs binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)): the plan artifact is contract-tier — `<contract_dir>/<slug>/PLAN.md` (default `docs/topics/`), committed on the task branch (or the memory tier under `contract_tier: local`) — and handoff notes are memory-tier under `<memory_dir>/handoffs/` (default `.work/handoffs/`).

## Arguments

`$ARGUMENTS` — optional mode or task description.

## Step 0: Detect Execution Mode

Before mode detection runs, apply a pre-execution discipline checklist by invoking `/andrej-karpathy-skills:karpathy-guidelines` (from the `karpathy-skills` marketplace) if that plugin is installed. It fires a four-rule discipline checklist (think-before-code, simplicity-first, surgical-changes, goal-driven-execution) ahead of the first Edit. Fallback is graceful: when the plugin is absent, hold to the same discipline directly — think before coding, prefer the simplest change that works, make surgical edits, keep the goal in view — and proceed without prompting.

Parse conversation context to determine execution mode. Mode shapes which context file to consult and how to structure the work.

| Signal in conversation | Mode | Context file |
|----------------------|------|-------------|
| Approved plan from a planning pass exists | **Feature** | [context/feature.md](context/feature.md) |
| Bug report, error diagnosis, or "fix" in conversation | **Bugfix** | [context/bugfix.md](context/bugfix.md) |
| Structural change, "refactor", "rename", "reorganize" | **Refactor** | [context/refactor.md](context/refactor.md) |
| Non-code changes (docs, config, YAML, markdown) | **Config** | Lighter workflow — no context file needed |

If `$ARGUMENTS` specifies a mode (`feature`, `fix`, `refactor`, `config`), use that. Otherwise infer from context. If ambiguous, ask.

**Detect orchestration mode** (distinct from implement execution mode above). Signals for orchestrated execution: the session runs autonomously (a goal/loop harness with no human in the turn cycle), or the approved plan routes phases to worker subagents. When either holds, after Step 1's prerequisite check passes, invoke `/implementation:implement-dispatch` via the Skill tool and follow its dispatch cadence for those phases instead of the Step 2 inline cadence. Interactive sessions with no worker routing use the classic inline cadence below. Step 1 runs in EVERY mode — orchestrated dispatch never skips the branch / plan / dirty-tree preflight.

**Read the relevant context file** for mode-specific guidance before proceeding.

## Step 1: Prerequisite Check

Before writing code, verify the knowledge base:

- **Is there an approved plan?** If yes, use it as execution roadmap. If no plan exists and the task is non-trivial (3+ files, new project, cross-cutting change), suggest a planning pass first — `/planning:plan` when the planning plugin is installed, otherwise whatever plan skill the consuming setup provides (check what's actually available; never invent skill names). For trivial changes (single-file fix, small config edit), proceed without a formal plan
- **Is the branch correct?** Check pre-computed branch. If on the default branch (`main`/`master`) and the project's workflow expects feature branches, stop and create one following the consuming project's branch-naming convention (check its `CLAUDE.md` / `AGENTS.md` / rules; `<type>/<description>` is a common default) — `git checkout -b <branch>`, or `/source-control:worktree` when that plugin is installed
- **Are there uncommitted changes?** If dirty working tree with unrelated changes, flag it — don't mix concerns in one commit

## Step 2: Execute with Incremental Validation

Core execution loop. Key discipline: **validate after each logical block, not just at the end.**

### Execution cadence

1. **Implement one logical block** — a single concern, function, class, or feature slice. Not the entire plan at once
2. **Build check** — invoke `/toolchain:check` (via Skill tool) for the affected ecosystem after each block when the `toolchain` plugin is installed; otherwise run the project's own build/test command directly. Catch compilation errors immediately, not after 5 files of changes. In non-interactive runs, tier the in-loop cost: typecheck/compile and the touched test files run per block; the broader affected-ecosystem test suite runs at phase boundaries and Step 5 — early detection stays, redundant full-suite passes go
3. **Test (TDD by default)** — when the `tdd` plugin is installed, invoke `/tdd:principles` via Skill tool **before writing the first test** for authoritative guidance on what to test, which testing style fits (output/state/communication), and when to mock. Then follow Red-Green-Refactor **one test at a time**: write a single failing test for the smallest slice of behavior, confirm it fails (red), implement the minimum to pass (green), refactor — then move to the next slice. **Do not write all tests upfront** — writing one at a time keeps each red signal observable (proving the test can fail before code makes it pass) and stops you over-fitting code to tests written against a design that doesn't exist yet. TDD is the fallback when the consuming project does not declare another testing cadence — skip only when genuinely impractical (e.g., pure infrastructure wiring with no testable logic, or UI rendering with no logic behind the seam), or when project policy says otherwise. A consumer can opt out in its `CLAUDE.md` / rules, for example: `Use tests-after for implementation work; do not use test-first TDD.` That project policy overrides this fallback and the mode context guidance
4. **Commit checkpoint** — commit after tests pass. Each commit should represent a green state. See below for commit discipline
5. **Repeat** until the plan is complete

**Integration-first within a multi-layer phase** — build the integration slice end-to-end first and verify it runs before fanning out across layers; it is the cheapest form of the Step 3 "plans are hypotheses" experiment.

### When to break the cadence

- **Build fails** → fix immediately. Don't add more code on top of broken code
- **Test fails unexpectedly** → investigate. An unexpected failure may signal a flawed approach, not just a bug
- **Scope creep** → if implementation reveals the task is bigger than planned, stop and replan — route back to the planning skill (`/planning:plan review` when installed) rather than expanding scope silently
- **Too-big-and-foggy (not just bigger)** → if implementation reveals the work is a sprawling set of still-undecided, not-yet-phrasable questions rather than a scoped change, stop building and name `/planning:wayfind` to the user — it charts the fog as a decision map upstream of the plan. Guide, never auto-switch

### Commit discipline

- **Commit after tests pass** — each commit is a green save point
- **Separate structural from behavioral commits** — a rename/extract gets its own commit, separate from new features (Tidy First: "make the change easy, then make the easy change")
- **Commit before running a simplify pass** — your working code is a save point. If simplification introduces a bad change, revert cleanly
- **Stage specific files** — `git add <file>`, never `git add -A` or `git add .`
- **Follow the consuming project's commit-message convention** (check its `CLAUDE.md` / rules; Conventional Commits is a common default). On squash-merge workflows, feature-branch messages matter less than the final squash subject

### Dependency direction

When implementing across components, respect the project's own dependency direction — implement the depended-upon components before the ones that depend on them, so each compiles against something that already exists. In a layered .NET/Clean-Architecture app, for example, that means inner Core/Domain types before outer Application/Infrastructure; a project with a different structure applies the same principle to its own layout.

## Step 3: Divergence Detection

Most important discipline in execution. Plans are hypotheses — implementation is the experiment.

**Divergence signals:**

- Build errors that suggest the approach won't work (not just typos)
- A dependency or API behaves differently than the plan assumed
- The implementation is significantly more complex than estimated
- You're writing workarounds or hacks to make the plan fit
- Tests reveal edge cases the plan didn't account for

**When divergence is detected:**

1. **Stop writing code.** Do not push through a broken approach
2. **NEVER declare something impossible without exhausting alternatives.** Before escalating to the user with "this can't be done," research deeper — check GitHub Issues for workaround flags, search for bypass options, test alternative APIs, look one investigation level beyond where you'd normally stop. Proper solution usually exists. Present "I've tried 2 things and they didn't work" as a progress update, not a conclusion
3. **Assess severity:**
   - **Minor** (typo in plan, small API difference) → fix inline, note the deviation
   - **Moderate** (approach needs adjustment but direction is right) → adjust the plan, document what changed and why. Research alternatives before adjusting — don't settle for workarounds when a proper solution may exist
   - **Major** (fundamental assumption was wrong) → run external research first to find alternative approaches (`/discovery:research` when the discovery plugin is installed, otherwise a disciplined multi-source lookup), THEN route back to the planning skill (`/planning:plan review` when installed) to re-plan. The user approved a plan that no longer works — they need to approve the new direction, informed by fresh research
4. **For major divergence:** switch to plan mode for safe exploration while redesigning the approach. Exit plan mode only after the revised plan is clear

**Non-interactive fork (autonomous runs only):** see `/implementation:implement-dispatch` "Divergence in non-interactive runs" — Moderate divergence takes the conservative option + a deviations log instead of deadlocking; Major still STOPS. Interactive sessions keep the escalation ladder above unchanged.

## Step 3.5: Scope-fence drift detector (run at every decision boundary)

**When**: at each phase boundary, at each worker-agent return, and BEFORE proposing any action not literally in the approved plan's work items.

**Discipline**: classify every proposed action against the plan before announcing it to the user. Three categories:

| Category | Definition | Action |
|---|---|---|
| **Plan work-item** | Literally appears in the plan's work-items list | Execute; report at phase boundary |
| **Plan-tagged fallback / execution-shape item** | The plan itself pre-tagged it as a contingency or execution-shape choice | If a fallback: surface to the user with `AskUserQuestion` — confirm/override/drop. If pre-approved execution shape: execute |
| **Invented mid-implement** | Not in the plan at all; surfaced by an agent return, anomaly, or implementation discovery | STOP. Classify (briefed-via-other-phase / plan-fallback / pure-invention / scope-expansion). Surface to the user with category tag + `AskUserQuestion`. NEVER batch with plan-anticipated items |

**Anti-pattern (canonical failure mode)**: batching invented follow-up actions with plan-anticipated items in one proposal. User pushback on the batch is structurally ambiguous — "drop both" reads as "drop all my proposals"; silent over-correction drops plan-anticipated work. Always separate categories at proposal time.

**Over-correction guard**: when the user pushes back on N proposed actions (≥2), NEVER silently drop all. Use `AskUserQuestion`:

```text
Q: You pushed back on N actions. Drop which?
Options:
- All N (drop everything I proposed)
- Only invented items (preserve plan-anticipated work)
- Specific items: <enumerate by category>
```

If the trap fires, document it in this session's retro — when the `session-flow` plugin is installed, surface it as an input to `/session-flow:retro`; otherwise note it in the completion summary.

## Step 4: Task Tracking and Phase-Boundary Handoff

For non-trivial implementations (3+ steps), use TaskCreate at the start:

- Create tasks for each major logical block from the plan
- Update tasks to `in_progress` when starting each block
- Update to `completed` after tests pass for that block
- Makes progress visible and survives context compaction

For trivial single-step implementations, skip the overhead.

### Phase-boundary discipline (the durable layer)

In-session task state lives in the harness and does not survive a context clear. The durable mirror is the plan artifact plus handoff notes. Where these live: resolve per the topic-docs binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)) — plan progress marked in the tracked plan file (`<contract_dir>/<slug>/PLAN.md`, default `docs/topics/`, on the task branch), handoff entries as timestamped notes in the memory tier's handoffs home. The plan is tracked, so marking progress is a diffable branch change, not a gitignored side file; the contract's runtime guards apply (the session's first contract-slice write runs `git check-ignore`).

**At every phase boundary** (the phase's sanity check passes), perform this ritual atomically:

1. **Verify acceptance criteria, then mark plan progress** — before setting the completed phase's tag to `[DONE]`, confirm the phase's acceptance criteria hold. Self-review is the floor; for any phase beyond a mechanical, behavior-preserving change (where an objective build/test/lint pass is verification enough), that verdict is rendered by an agent that did NOT produce the phase's changes — a fresh-context verifier handed binary criteria and the diff, withholding your rationale, or the cross-vendor option `/verification:confirm` names — never the producing context auditing itself, which converges on approval rather than detection. Then set the tag to `[DONE]` in the plan artifact and tick its step boxes; keep any parent/roadmap documents that mirror phase status in sync in the same turn
2. **Write a phase-boundary handoff entry** — when the `session-flow` plugin is installed, invoke `/session-flow:handoff` via the Skill tool (file method, topic `phase-N`) — that skill owns the handoff surface and format; otherwise write a timestamped handoff note to the memory tier's handoffs home (`<memory_dir>/handoffs/`, default `.work/handoffs/`, per [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)). When that skill is present it defines which sections the note carries — do not restate them here. Without it, this skill owns the fallback shape, so the note must stand on its own: what shipped, the decisions made and why, the approaches tried and ruled out, the files modified, anything already applied that must not be repeated, and the ordered remainder of the work — plus the two items specific to a phase boundary, the sanity-check evidence for the phase just closed and the pointer into the next phase. A note carrying only the latter two forces the next session back into the diffs, which is the rediscovery the paragraph below says this ritual prevents
3. **Update the status summary** in the topic's memory slice (`<memory_dir>/<slug>/`, default `.work/`) — current phase, next concrete action, blockers, pointer to the newest handoff entry
4. **Commit** the plan changes alongside the phase's source-code changes in a single commit — under `contract_tier: branch` (the default) the plan is tracked on the task branch, so every phase commit carries plan marks and source together: one commit, one story. Under `contract_tier: local` the plan lives in the self-ignored memory slice and is never staged — phase commits carry source only, plan marks update in place. Mark-then-commit, never the reverse: committing the phase's work first and marking DONE in a follow-up commit forces a second commit just to record it. Memory-tier files (status summary, handoffs) never enter the commit — that tier self-ignores. Do NOT present or run the commit until steps 1-3 are in the working tree. When git is owned by the user, still complete steps 1-3 FIRST so the marking is in the working tree when they commit
5. **Emit the next-phase resume prompt** at the end of the response when the plan has a Phase N+1 still `[TODO]` — a short self-contained prompt a fresh session can start from cold (status summary + plan). When the final phase is done, emit a completion resume prompt for the plausible next step (review pass, retro, or PR) instead of merely a prose summary. Skip only when the sanity check failed or the user said "stop after this"

**Why every phase, not just session-end:** clearing context between phases must be cheap. Without per-phase handoff entries, a resumed session has to read source diffs to reconstruct what was tried; with them, it reads the status summary plus the most-recent handoff entry and knows everything material. Cost: 30s-2min per phase boundary. Skip-cost: hours of rediscovery on the next resume.

**Mid-phase handoff is still appropriate** when context is heavy or a pause is imminent — write an ad-hoc handoff note (topic e.g. `wip-checkpoint`). The phase-boundary ritual above is the automatic baseline; ad-hoc handoffs add extra save points.

In orchestrated runs, the orchestrator may stay resident across phase boundaries instead of clearing — criteria per `/implementation:implement-dispatch` "Resident-vs-clear at phase boundaries"; the ritual above is unchanged either way.

## Step 5: Completion and Handoff

When all planned work is done:

1. **Final build check** — invoke `/toolchain:check` via the Skill tool for all affected ecosystems when the `toolchain` plugin is installed; otherwise run the project's own build/test command
2. **Run all affected tests** — not just the ones you wrote, but tests that could be impacted by your changes
3. **Self-review (a floor, not the final verdict)** — the producing context converges on approval, so this catches slips but does not render the outcome verdict (step 5 hands to `/verification:confirm`, which renders it from outside the producing loop). Read through changes (`git diff HEAD~N`) looking for:
   - Consistency with existing patterns
   - No debugging artifacts left behind
   - No commented-out code
   - No TODO comments that should be actual work
4. **Rubber-duck advisor checkpoint (HIGH/CRITICAL only)** — for changes involving concurrency, security, cross-platform behavior, external API integration, or with significant divergence from the original plan, call the `advisor` tool (when available in the session) for a quick cross-model critique pass before the review gate. Skip for trivial changes
5. **Hand off to the pre-PR sequence** — run `/verification:confirm` for outcome verification when the `verification` plugin is installed (otherwise self-verify the outcome against the plan/intent directly), then suggest the project's review/PR flow (`/review:quality-gate` and `/source-control:pull-request` when those plugins are installed; otherwise whatever the consuming setup provides — the user controls timing). Do not commit-and-push unilaterally — final staging and PR creation belong to that flow

## Skill chaining during execution

| Condition | Action |
|-----------|--------|
| Before writing first test | Invoke `/tdd:principles` via Skill tool (when installed) for test design guidance |
| After each logical block | Invoke `/toolchain:check` via Skill tool (when the `toolchain` plugin is installed; else the project's own build) |
| At every phase boundary | Run the Step 4 ritual (plan marks + handoff entry + status + commit + resume prompt) |
| Worker-routed phase or autonomous orchestration | Invoke `/implementation:implement-dispatch` via Skill tool |
| Divergence detected (major) | Route back to the planning skill (`/planning:plan review` when installed) |
| Technical question mid-implementation | `/discovery:research` (when installed), otherwise disciplined multi-source research |
| HIGH/CRITICAL change at completion | Call the `advisor` tool — rubber-duck checkpoint before review |
| All implementation complete, tests pass | `/verification:confirm` (when the `verification` plugin is installed; else self-verify against intent), then suggest the project's review/PR flow (`/review:quality-gate`, `/source-control:pull-request` when installed) |

## What This Skill Does NOT Do

- **Does not replace Claude's coding ability** — provides execution discipline, not implementation instructions
- **Does not auto-execute plans** — guides execution with checkpoints and validation. Code changes are still judgment calls
- **Does not replace `/verification:confirm`** — the `verification` plugin's outcome-verification skill (a separate plugin, when installed) does comprehensive build + test + lint + outcome verification. This skill does incremental validation during implementation
- **Does not produce plans** — a planning pass does. If the plan needs revision, this skill routes back to it
- **Does not replace `/toolchain:check`** — the `toolchain` plugin's check skill (a separate plugin, when installed) is the SSOT for build commands; this skill invokes it at the right moments and falls back to the project's own build command when that plugin is absent
- **Does not orchestrate workers** — `/implementation:implement-dispatch` owns the orchestrated dispatch cadence for worker-routed phases and autonomous runs. This skill detects the routing and chains to it

## Gotchas

- **Don't skip the branch check.** Writing code on the default branch in a PR-based workflow means rewriting history later. Catch the mistake before the first edit
- **Don't implement the entire plan before testing.** Incremental cadence exists because large batches of untested code hide compounding errors. Build and test after each logical block
- **Divergence is not failure.** Plans are hypotheses. Detecting that an approach won't work and replanning is the skill working correctly — pushing through despite signals is the failure
- **NEVER declare "impossible" without exhausting alternatives.** When an approach fails, research deeper before giving up. Check GitHub Issues for workaround flags, search for bypass options, try alternative APIs. Proper solution often exists one investigation level beyond where you'd normally stop
- **Commit checkpoints are save points, not polish points.** Don't agonize over commit messages on feature branches when the workflow squash-merges — commit freely
- **Config/docs changes still need verification.** Even non-code changes can break builds (`.editorconfig` changes, project-file modifications, markdown lint). Run `/verification:confirm` for these too
- **Scope-fence drift detector at every decision boundary (Step 3.5).** Phase boundaries, agent returns, and anomaly-handoff moments are where invented work creeps in disguised as plan-anticipated work. Classify before announcing
- **Over-correction guard on user pushback.** When the user pushes back on N proposed actions (≥2), ask per-category — never silently drop all. The pushback identifies a problem with at least one action, not necessarily all
