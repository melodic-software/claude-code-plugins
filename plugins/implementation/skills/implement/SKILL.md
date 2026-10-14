---
description: "Inline code changes with incremental validation: TDD by default, a build and test check after each logical block, commits at green checkpoints, and a route back to planning when the approach breaks. Use when executing an approved plan, fixing a bug, refactoring, rewriting, migrating or porting code, changing config, or whenever code is about to be written: 'implement this', 'execute the plan', 'fix this bug', 'refactor', 'build this', 'write the code', 'make this change', 'apply the plan'."
argument-hint: "[feature|fix|refactor|replace|config] [task]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Execute approved plans with TDD, incremental validation, and green commits
---

**Arguments.** `[feature|fix|refactor|replace|config] [task]`. e.g., /implementation:implement, /implementation:implement feature, /implementation:implement fix login-bug, /implementation:implement refactor, /implementation:implement replace legacy-parser

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation (a worktree-isolated session refuses a compound command that contains git):

- Current branch, `git branch --show-current`
- Working tree status (empty = clean), `git status --porcelain | head -20`
- Recent commits, `git log --oneline -5`
- Uncommitted changes, `git diff --stat HEAD | tail -1`

Keep the pipe in the command: the Bash tool returns the full output before anything can be cut.
Treat a failure (not a repository, git unavailable) as an unknown value and carry on.

## Purpose

Execute an approved plan, a fix or a change incrementally: validate after each block, commit at
green checkpoints, and route back to planning the moment the approach stops working rather than
discovering it at PR review. Planning comes before this skill; `/testing:plan`, `/testing:write`,
`/testing:diagnose` and `/verification:confirm` validate the result when installed.

Track Steps 0–5 in the session task list. Durable progress lives in the plan artifact (phase tags,
`- [ ]` step boxes) and the handoff notes Step 4 writes; keep no second checklist file. Placement
follows the lifecycle artifact protocol
([`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md)):
the plan is `<memory_dir>/<slug>/PLAN.md` (default `.work/`), never committed; handoff notes go
under `<memory_dir>/handoffs/` (default `.work/handoffs/`).

## Settings

Each key below resolves once per run from three layers, lowest first: the default; the user's
option (a literal, unexpanded placeholder means unset); and the key in the repository's
`docs/conventions/implementation.yaml`, which wins when set, read under the root rule in
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md). A value
outside the key's values is named with its file or option, the key and the value, and that layer is
dropped: the repository's valid value still wins over an invalid user value, and an invalid
repository value resolves the default, never the user's value. Report one line per key with the
layer that supplied it, for example `per_unit_check: every (docs/conventions/implementation.yaml)`.

| Key | User option | Values (default first) | Resolved |
|---|---|---|---|
| `code_writing` | `${user_config.code_writing}` | `inline`, `dispatch` | Step 0 |
| `integration_posture` | `${user_config.integration_posture}` | `by-kind`, `day-one`, `minimal` | Step 0, only with no approved plan |
| `refactor_compat` | `${user_config.refactor_compat}` | `same-wave`, `deprecate` | refactor mode, in [context/refactor.md](context/refactor.md) |
| `per_unit_check` | `${user_config.per_unit_check}` | `pilot`, `every` | the first multi-site block (Step 2) |
| `verify_mechanical_phases` | `${user_config.verify_mechanical_phases}` | `false`, `true` | before the first phase boundary (Step 4); a floor, per config.md: `true` in any layer wins, and an invalid value counts as unset |

## Arguments

`$ARGUMENTS`, optional mode or task description.

## Step 0: Detect Execution Mode

In fix and config modes, hold to the scope discipline: do the simplest thing that works, edit a file surgically rather than rewriting it when the result is the same, and add no features, abstractions, or cleanup the task does not require. A feature follows `integration_posture` below, and so do fix and config when it resolves `day-one`; a refactor keeps the plan's scope. Proceed without prompting.

**Data boundaries.** Check and narrow values where they enter the system (request bodies, files read, other services' responses) into the types the code works with, and past that point rely on those types instead of checking them again. Pointer: the "Overeagerness" section of Anthropic's prompting best practices ([claude-prompting-best-practices#overeagerness](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices#overeagerness); as of 2026-10-04; recheck when that section drops or moves its boundary-validation advice).

Pick the mode, then read its context file before proceeding:

| Signal in conversation | Mode | Context file |
|----------------------|------|-------------|
| Approved plan from a planning pass exists | **Feature** | [context/feature.md](context/feature.md) |
| Bug report, error diagnosis, or "fix" in conversation | **Bugfix** | [context/bugfix.md](context/bugfix.md) |
| Structural change, "refactor", "rename", "reorganize" | **Refactor** | [context/refactor.md](context/refactor.md) |
| A new implementation takes over from an old one that must behave the same: "rewrite", "migrate", "port", "replace X with Y" | **Replace** | [context/replace.md](context/replace.md) |
| Non-code changes (docs, config, YAML, markdown) | **Config** | Lighter workflow, no context file needed. Verification is not lighter: non-code changes still break builds (`.editorconfig`, project files, markdown lint), so invoke `/verification:confirm` via the Skill tool for these too |

**`refactor_compat`.** In refactor mode, [context/refactor.md](context/refactor.md) resolves it (user option in Settings) against the repository file and states what each value does with the old shape.

A mode named in `$ARGUMENTS` (`feature`, `fix`, `refactor`, `replace`, `config`) wins; otherwise infer it, and ask when ambiguous.

**Orchestration mode.** Dispatch instead of editing inline when the session runs autonomously (a goal/loop harness with no human in the turn cycle), the approved plan routes phases to worker subagents, or `code_writing` resolves `dispatch`. Then, after Step 1 passes, invoke `/implementation:implement-dispatch` via the Skill tool and follow its cadence for those phases instead of Step 2's; under `dispatch` that is every phase. Otherwise (interactive, no worker routing, `code_writing: inline`) use the inline cadence below. Step 1 runs in every mode.

**`code_writing`.** Resolve it here (Settings). With no approved plan (a trivial change Step 1 lets through without one) there are no phases to hand out, so the inline cadence runs and the report line says so.

**`integration_posture`.** How far the change reshapes the code around it. With an approved plan, follow the plan's scope and do not resolve the key (`/planning:plan` already wrote any redesign into the plan); report `integration_posture: plan governs`. With no approved plan, resolve it (Settings) once the mode is known, report e.g. `integration_posture: minimal (docs/conventions/implementation.yaml)`, and apply it by mode:

| Mode | `by-kind` | `day-one` | `minimal` |
|---|---|---|---|
| Feature | day-one redesign | day-one redesign | minimal |
| Fix, Config | minimal | day-one redesign | minimal |
| Refactor | plan scope, behavior unchanged | plan scope, behavior unchanged | plan scope, behavior unchanged |

A day-one redesign changes the code the work lands in until it reads as though the new behavior had been part of the original design: move, rename, merge or split what that code already has, instead of adding a branch or a flag beside it. It stays inside the files the change already touches and leaves behavior outside the task unchanged. Minimal is the scope discipline at the top of this step.

When the mode signals conflict (a "fix" that adds a capability, a config edit that changes code paths) and no argument names the mode, an interactive run asks. A non-interactive run (no human in the turn cycle) takes `minimal`, whatever the resolved value, and appends a deviation entry to `DEVIATIONS.md` in this work's memory slice (`<memory_dir>/<slug>/`, default `.work/`), typed per `/implementation:implement-dispatch` "Divergence in non-interactive runs": plan said nothing (no approved plan), found the conflicting signals, chose `minimal`, revisit at PR review.

## Step 1: Prerequisite Check

Before writing code:

- **Approved plan?** If yes, it is the roadmap. If not, and the diff will not be quick to review or cheap to retry (a new project, a cross-cutting change, or any diff that adds types, public contracts, or module boundaries), suggest locking the contract first: `/planning:interview` when installed (it hands off to `/planning:plan`), otherwise whatever interview or plan skill the setup actually provides; never invent skill names. A diff that is quick to review and cheap to retry proceeds without a plan and is reviewed afterward; if it turns out not to be quick to review, stop and route back to `/planning:interview`
- **Correct branch?** On the default branch (`main`/`master`) when the project expects feature branches, stop and create one per the project's branch-naming convention (its `CLAUDE.md` / `AGENTS.md` / rules; `<type>/<description>` is a common default): `git checkout -b <branch>`, or `/source-control:worktree` when installed
- **Uncommitted changes?** Flag unrelated dirty-tree changes; don't mix concerns in one commit
- **Current base?** Before the first build or test run, fetch the base branch and bring this branch onto it the way the project integrates (merge or rebase; a brief or user instruction that forbids either wins), so a failure belongs to the real base. With no remote, or a failed fetch, say so in one line and carry on

## Step 2: Execute with Incremental Validation

Validate after each logical block, not just at the end.

### Execution cadence

1. **Implement one logical block**: a single concern, function, class, or feature slice, never the whole plan at once
2. **Build check**: invoke `/toolchain:check` (Skill tool) for the affected ecosystem after each block when installed; otherwise run the project's own build/test command. In non-interactive runs, run typecheck/compile and the touched test files per block, and the broader affected-ecosystem suite at phase boundaries and Step 5
3. **Test (TDD by default)**: when the `tdd` plugin is installed, invoke `/tdd:principles` (Skill tool) **before writing the first test**. Then Red-Green-Refactor **one test at a time**: one failing test for the smallest slice of behavior, confirm it fails (red), implement the minimum to pass (green), refactor, next slice. **Do not write all tests upfront**: one at a time keeps each red signal observable and stops code over-fitting tests written against a design that doesn't exist yet. **Minimum to pass means the smallest correct implementation, not the smallest text that turns the bar green**: never hardcode the test's expected values, special-case its inputs, or weaken an assertion; if a test seems wrong, fix it deliberately and say so. TDD is the fallback when the project declares no other testing cadence; skip it only when genuinely impractical (pure infrastructure wiring with no testable logic, UI rendering with no logic behind the seam) or when project policy opts out in its `CLAUDE.md` / rules (e.g. `Use tests-after for implementation work; do not use test-first TDD.`), which overrides this fallback and the mode context guidance
4. **Commit checkpoint**: commit after tests pass; each commit is a green state (see Commit discipline). The one exception is a declared span: a phase whose plan carries a `**Planned breakage:**` line (`<build | tests | lint> red until Phase <M> for <paths or test filter>: <reason>`) opens a span that ends when Phase `<M>` lands. At the span's first block, record the failure set the named step produces before any edit. Inside the span a red commit is allowed only when every new failure lies in the declared paths or test filter; its body names the span (`Planned breakage: tests red until Phase 3 for tests/billing/`). A failure outside the declaration is a real failure: stop and handle it under "When to break the cadence", and never widen the declaration to cover it. Without a declaration every commit is green
5. **Repeat** until the plan is complete

**Multi-site step (lever check)**. Before a block that applies one change at three or more sites (count the sites that get the same edit, not the files), invoke `/discipline:script-the-deterministic-work lever-check <block summary>` via the Skill tool when it is among the available skills, and follow its `build-a-lever` or `edit-by-hand` answer. When it is not available, apply its `deterministic` rule: build a lever only when each site's edit follows from that site's text alone, and say in one line that the check ran on `deterministic` because the discipline skill was unavailable. With `build-a-lever`, edit the first site by hand, run the lever on a clean copy of that site, diff the two, fix the lever until they match, then run it on the rest. The lever's run goes through the same build check and commit checkpoint as any block.

**Per-unit check (`per_unit_check`)**. Apply the lever or hand edit unit by unit (a unit is one site, or one file holding several sites) under this key (Settings):

- `pilot`: apply the change to a small first batch, run the build check and the tests covering it, and fix the lever or edit until that batch is green; then apply it to every remaining unit and run one check over all of them. Size the batch from the "Fan out across files" section of the Claude Code best practices ([best-practices#fan-out-across-files](https://code.claude.com/docs/en/best-practices#fan-out-across-files); as of 2026-10-04; recheck when that section changes its pilot advice or moves). A failure in the final check is handled under "When to break the cadence", not by re-running the whole set.
- `every`: run the build check and the affected tests after each unit, and move on only once it passes.

Either way the commit checkpoint follows the last green check.

**Revert a unit that does not move the check**. When a block meant to turn a failing check green, or change how it fails, leaves the check reporting the same result, revert the block to the last green commit instead of patching forward, then try the next hypothesis; inside a declared planned-breakage span revert to the start of that span instead.

**Integration-first within a multi-layer phase**. Build the integration slice end-to-end and verify it runs before fanning out across layers.

### When to break the cadence

- **Build fails** → fix it before adding more code
- **Test fails unexpectedly** → investigate; it may signal a flawed approach, not just a bug
- **Scope creep** → if the task is bigger than planned, stop and replan (invoke `/planning:plan review` via the Skill tool when installed) rather than expanding scope silently
- **Technical question mid-implementation** → invoke `/discovery:research` via the Skill tool when installed, otherwise run disciplined multi-source research
- **Too-big-and-foggy (not just bigger)** → if the work is a sprawl of still-undecided questions rather than a scoped change, stop building and name `/planning:interview` to the user (it escalates to `/planning:wayfind` when the effort outgrows one session). Guide, never auto-switch

### Commit discipline

- **Commit after tests pass**, except a red commit inside a declared planned-breakage span
- **Default delivery order**: commits that delete code go ahead of the commits that build on what is left, and in a fix the commit holding the failing test goes ahead of the fix. Under a project-declared tests-after cadence the failing-test commit is optional
- **Separate structural from behavioral commits** (Tidy First: "make the change easy, then make the easy change")
- **Commit before running a simplify pass**, so a bad simplification reverts cleanly
- **Stage specific files**: `git add <file>`, never `git add -A` or `git add .`
- **Fix the finding, never silence it**: add no lint or type-checker suppression (`eslint-disable`, `# noqa`, `# type: ignore`, `#pragma warning disable` and the like) to turn a check green. The exception is a false positive you have shown to be one: its suppression names the rule id, where the tool can name one, and states why the finding is wrong there. A project's own instructions override this rule where they say otherwise
- **Follow the project's commit-message convention** (its `CLAUDE.md` / rules; Conventional Commits is a common default). On squash-merge workflows, feature-branch messages matter less than the final squash subject

### Dependency direction

Implement depended-upon components before the ones that depend on them, following the project's own dependency direction (in a layered Clean-Architecture app, Core/Domain before Application/Infrastructure).

## Step 3: Divergence Detection

Plans are hypotheses; implementation is the experiment.

**Divergence signals:**

- Build errors that suggest the approach won't work (not just typos)
- A dependency or API behaves differently than the plan assumed
- The implementation is significantly more complex than estimated
- You're writing workarounds or hacks to make the plan fit
- Tests reveal edge cases the plan didn't account for

**Design signals.** Before filing friction as a plan problem, compare what you just did with these rows. A match means the design, not only the plan, may have to go.

| You just | For example | It points to |
|---|---|---|
| Weakened a type so the type checker would pass | A `# type: ignore[...]` on the new line, a parameter widened to `object`, a property taken out of a schema's `required` list | A boundary in the wrong place |
| Made a caller work by having it lean on a module's internals | A script that parses another script's log text instead of reading its exit code | A boundary in the wrong place |
| Added a lock or a retry to settle a race or an ordering bug that would not exist if another component owned the state | Two workers in one wave appending to `DEVIATIONS.md` behind a lockfile, where the race would not exist if the orchestrator owned the file | State owned by the wrong component |
| Hit one cause a second time | Two or more `DEVIATIONS.md` entries that trace to one cause, or a workaround about to be copied to a second file | A problem the plan cannot absorb |

Length is not a row: code that parses a messy format, such as a transcript JSONL file, can run long in a sound design; judge where it is divided, not how many lines it has.

**When divergence is detected:**

1. **Stop writing code.** Do not push through a broken approach
2. **Research before declaring something impossible.** Look one level deeper (the dependency's issue tracker, workaround flags, bypass options, alternative APIs). Present "I've tried two things and they didn't work" as a progress update, not a conclusion
3. **Assess severity:**
   - **Minor** (typo in plan, small API difference) → fix inline, note the deviation
   - **Moderate** (approach needs adjustment, direction is right) → research alternatives rather than settling for a workaround, then adjust the plan and document what changed and why
   - **Major** (fundamental assumption was wrong) → run external research first (`/discovery:research` via the Skill tool when installed, otherwise a disciplined multi-source lookup), THEN route back to planning (`/planning:plan review` via the Skill tool when installed). The user approved a plan that no longer works; they approve the new direction
4. **For major divergence:** switch to plan mode while redesigning. Exit plan mode only when the revised plan is clear and its first draft answers yes to each check: Is it smaller than the failed attempt? Does it list what it drops before what it adds? Does it start from the goal and what the failed attempt proved, never from the broken code?

**Non-interactive fork (autonomous runs only):** see `/implementation:implement-dispatch` "Divergence in non-interactive runs". Moderate divergence takes the conservative option plus a deviations log instead of deadlocking; Major still STOPS. Interactive sessions keep the ladder above.

**Opt-in deviation log (interactive):** an interactive session may keep the same append-only `DEVIATIONS.md` beside the plan artifact, typing entries per that contract (plan-confirmed / discovery / deviation / human-decision; a deviation answers plan said / found / chose / revisit). Opt in when the session is long, the plan is contested, or a handoff is likely: the Moderate rung's record then survives, and Step 5's fold-back reads it.

## Step 3.5: Scope-fence drift detector (run at every decision boundary)

**When**: at each phase boundary, at each worker-agent return, and BEFORE proposing any action not literally in the approved plan's work items. Classify every proposed action before announcing it:

| Category | Definition | Action |
|---|---|---|
| **Plan work-item** | Literally appears in the plan's work-items list | Execute; report at phase boundary |
| **Plan-tagged fallback / execution-shape item** | The plan itself pre-tagged it as a contingency or execution-shape choice | If a fallback: surface to the user with `AskUserQuestion`, confirm/override/drop. If pre-approved execution shape: execute |
| **Invented mid-implement** | Not in the plan at all; surfaced by an agent return, anomaly, or implementation discovery | Stop. Classify (briefed-via-other-phase / plan-fallback / pure-invention / scope-expansion). Surface to the user with category tag + `AskUserQuestion`, separately from plan-anticipated items |

**Never batch invented follow-ups with plan-anticipated items in one proposal**: pushback on a mixed batch is ambiguous, and "drop both" silently drops plan work.

**Over-correction guard**: when the user pushes back on two or more proposed actions, do not silently drop all of them. Use `AskUserQuestion`:

```text
Q: You pushed back on N actions. Drop which?
Options:
- All N (drop everything I proposed)
- Only invented items (preserve plan-anticipated work)
- Specific items: <enumerate by category>
```

If the trap fires, record it for this session's retro: an input to `/session-flow:retro` when installed, otherwise a note in the completion summary.

## Step 4: Task Tracking and Phase-Boundary Handoff

For non-trivial implementations (3+ steps), track each major block from the plan as a task, marking it complete only after its tests pass. Skip this for single-step work.

### Phase-boundary discipline (the durable layer)

Task state does not survive a context clear; the plan artifact and handoff notes do (placement: the artifact protocol above). Plan progress is marked in `<memory_dir>/<slug>/PLAN.md` and handoff entries are timestamped notes in the memory slice's handoffs home. Both are self-ignored and never committed, so when marking changes the plan, refresh its paste in the pull request body or the linked issue. Write that body refresh before the push that carries the phase's commit, or after the last push's CI run has finished, never as its own edit right after a push: a body edit re-runs every workflow that triggers on `edited`, adding a second run on the same head.

**At every phase boundary** (the phase's sanity check passes), perform this ritual atomically, in order:

1. **Verify acceptance criteria, then mark plan progress**. Confirm the phase's acceptance criteria before setting its tag to `[DONE]`. Self-review is the floor. For any phase beyond a mechanical, behavior-preserving change (where an objective build/test/lint pass suffices), and for every phase when `verify_mechanical_phases` resolves `true` (Settings; report the value and its layer), the verdict comes from an agent that did NOT produce the changes: a fresh-context verifier handed binary criteria and the diff, without your rationale, or the cross-vendor option `/verification:confirm` names; never the producing context auditing itself, which converges on approval. Then set the tag to `[DONE]`, tick its step boxes, and sync any parent/roadmap documents that mirror phase status in the same turn
2. **Update the status summary** in the memory slice (`<memory_dir>/<slug>/`): current phase, next concrete action, blockers, and a resume pointer. When step 4 writes a handoff entry, the pointer names it by its topic (the newest `phase-N` note in `<memory_dir>/handoffs/`, not yet written when this step runs); otherwise it names the PLAN.md path and the next phase
3. **Commit** the phase's source changes in a single commit; plan and memory-slice files never enter it. Do not present or run the commit until steps 1-2 are done. When git is owned by the user, still finish steps 1-2 FIRST and hand them the commit before step 4
4. **Route the continuation, last**. Phases of one approved plan are one task, so a boundary does not by itself end the turn. Write a handoff entry and stop only on this skill's own conditions: a model or domain switch for the next phase, the end of the run, a commit gate only the user can pass, or the work moving to another session or checkout. Everything else about the window (keep going, compact, clear or hand off, including a heavy window, a pause, repeated failed corrections, an already-compacted run whose output is degrading, and the step into review) goes to `/session-flow:workflow`, handed the PLAN.md path and the next phase. A compaction is the user's to type; an unattended run relies on automatic compaction. Without session-flow, see <https://code.claude.com/docs/en/context-window#when-your-context-fills-up>. Writing a handoff entry ends the turn. When `session-flow` is installed, invoke `/session-flow:handoff` via the Skill tool (file method, topic `phase-N`); it owns the note's surface, sections and format, and its STOP gate ends the turn; never write the note free-hand. Otherwise write a timestamped note to `<memory_dir>/handoffs/` (default `.work/handoffs/`) that stands on its own: what shipped, the decisions made and why, the approaches tried and ruled out, the files modified, anything already applied that must not be repeated, the ordered remainder of the work, the sanity-check evidence for the phase just closed, and the pointer into the next phase. The fallback note ends with, and the response prints, a copy region in exactly the engine's shape: the copy-instruction line, a top rail, the `Read @` directive, the `Prior session:` line, the `Handoff origin:` line, the `Next:` line carrying one to five headline lines (or `Next: none (closed)` alone, for a closing handoff), and a bottom rail

   ```text
   `/clear`, then copy everything between the dashed lines:

   ──────────────────────────────────────────────────────────
   Read @<handoffs-dir>/<TS>-handoff-<topic>.md, confirm its Original goal still governs the remaining next steps, then continue them.
   Prior session: <UUID>.
   Handoff origin: <remote URL, userinfo stripped> <repo-relative path>
   Next:
   <first remaining action, one plain headline line, no bullet>
   <second remaining action, or delete this line>
   ──────────────────────────────────────────────────────────
   ```

   That copy region, from the handoff skill or the fallback note, is the next-phase resume prompt: with a Phase N+1 still `[TODO]`, its `Next:` lines start that phase from cold (status summary + plan); when the final phase is done, they name the plausible next step (review pass, retro, or PR) instead of a prose summary. Leave the resume prompt out only when the sanity check failed or the user said "stop after this"

**Mid-phase**, when a pause is imminent, the user reports the session is heavy, a context-measuring mechanism says to fork, or the responses are drifting, route the next step with `/session-flow:workflow` (topic for any handoff it routes to, e.g. `wip-checkpoint`). Never on your own estimate of the remaining window: a budget reading is a measurement, not a decay signal. Entering implementation from a finished plan still starts in a fresh session.

- **Pointer**: for what to do when the window fills, see <https://code.claude.com/docs/en/context-window#when-your-context-fills-up>.
- **As of**: 2026-10-02
- **Recheck trigger**: that section changes its `/compact` or `/clear` guidance.

In orchestrated runs the orchestrator may stay resident across phase boundaries instead of clearing, per `/implementation:implement-dispatch` "Resident-vs-clear at phase boundaries"; a boundary that clears runs the ritual above in full, and a resident one runs the reduced form that skill's "Phase boundaries" section defines.

## Step 5: Completion and Handoff

When all planned work is done:

1. **Final build check**: `/toolchain:check` via the Skill tool for all affected ecosystems when installed; otherwise the project's own build/test command
2. **Run all affected tests**, including the ones you wrote and any your changes could impact. This end gate is always green: a planned-breakage declaration covers only its span, never the completed work
3. **Self-review (a floor, not the final verdict; step 6's `/verification:confirm` renders that)**. Read the changes (`git diff HEAD~N`) for:
   - Consistency with existing patterns
   - No debugging artifacts, commented-out code, or TODO comments that should be actual work
   - No scratch verification scripts committed as permanent tests; committed tests are sized like their neighbors, roughly one focused test per stated behavior
   - No fixes, optimizations, or extensions outside the task; report anything noticed nearby as a follow-up in the summary instead
4. **Deviation fold-back**. When a `DEVIATIONS.md` exists for this work, read it and emit one plan-amendment bullet per unresolved deviation or human-decision entry: what the plan should say next time, or what still needs a person. Fold the bullets into the phase-boundary plan updates or the handoff summary
5. **Rubber-duck advisor checkpoint (HIGH/CRITICAL only)**. For changes involving concurrency, security, cross-platform behavior, external API integration, or significant divergence from the plan, call the `advisor` tool (when available) for a cross-model critique before the review gate. Skip for trivial changes
6. **Hand off to the pre-PR sequence**, in its own order (invoke `/session-flow:workflow pre-pr` via the Skill tool when installed; otherwise the setup's own pre-PR checklist). Review comes before outcome verification, because the simplify pass sits between them and verification must judge the code that ships. So: first suggest the Test-stage checks the change still needs (see Next), then the review flow (`/review:quality-gate` when installed, else the setup's review step), then `/verification:confirm` once the diff is final (when installed; otherwise self-verify the outcome against the plan/intent), then the PR (`/source-control:pull-request` when installed, otherwise whatever the setup provides; the user controls timing). Do not commit-and-push unilaterally: final staging and PR creation belong to that flow. A run that ends without outcome verification against the Brief's outcome criteria states in the handoff summary, or in `DEVIATIONS.md` when one exists, that it did not run and why. In an orchestrated run, a source commit the orchestrator makes after the last phase gets the `phase-verifier` verdict before it is pushed, per `/implementation:implement-dispatch` "Phase boundaries"
7. **Completion reply**. Say what now exists, and wherever the plan or task left a call to you, which way you went and why. Close by putting to the user every decision that is still theirs, each with your recommendation, or by saying none remain

## Boundaries

- Provides execution discipline; it does not produce plans (a planning pass does, and this skill routes back to it) or orchestrate workers (`/implementation:implement-dispatch` owns worker-routed phases and autonomous runs).
- `/toolchain:check` owns build commands and `/verification:confirm` owns outcome verification, each when installed; this skill invokes them at the right moments and falls back to the project's own commands.

## Next

- Coverage of the change not yet planned: `/testing:plan`.
- Tests written during the work, their quality unchecked: `/testing:audit`.
- A runtime-affecting change (UI, API, service, hook, script): `/testing:run-e2e`.
- Tests planned, checked and green: `/review:quality-gate`.

## Gotchas

Observed failure patterns are in [context/gotchas.md](context/gotchas.md). Read it before the first edit of an implementation session, and again at any stall point: a second workaround, a build error you are about to defer, a commit about to mix concerns. When a new pattern bites, record it in the topic's memory slice (`<memory_dir>/<slug>/`) as one lesson per file with a one-line summary at the top, in the same what-happens / why-it-is-bad / how-to-avoid shape, and consult that slice at the start of later sessions on the same topic. Do not edit the plugin's own file from a consuming project.
