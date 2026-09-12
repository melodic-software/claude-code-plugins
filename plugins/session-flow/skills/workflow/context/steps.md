# Workflow Stages: Full Definitions

The staged development workflow plus the optional contract stage. When the consuming repo defines a
skill for a stage, invoke it; otherwise execute the stage inline per its definition here.

## 0. Contract (optional: lock the brief before building)

Drive fuzzy intent to a zero-ambiguity contract before behavior-changing work: goal, constraints,
acceptance criteria, captured assumptions. Persist it (a plan file in the repo's artifact location)
so later stages aim at an explicit target instead of inferring one mid-task.

- Trigger conditions: intent is fuzzy, scope is uncalibrated, or the work changes behavior,
  structure, or contracts
- Skip conditions: one-line bug fixes, or follow-ups where the contract IS the conversation
- Front-loads clarification cost in one round-trip; ask the questions the design turns on one at a
  time, highest architectural blast radius first

## 1. Explore

Structured local codebase exploration: read the relevant code, git history, file layout, tests, and
dependencies. Understand current state before changing anything.

- Survey breadth-first (glob/grep), confirm the files the change touches, then read those in full
- When files referenced in git status or history don't exist on disk, ask before investigating.
  They may be intentionally deleted

## 2. Research

External verification of technical claims: official docs, primary sources, current versions.

- No claim the work depends on is accepted without verified, current information from authoritative
  sources
- **Task size does NOT reduce research depth.** A one-line config change gets the same
  verification rigor as a multi-file feature
- Reading a document and restating its conclusions is not research. Analysis requires independent
  verification

## 3. Plan

Structured plan with rationale, test strategy, and a user approval gate before execution begins.

- Include what will change, why, in what order, and how success is verified
- Plan depth scales to blast radius. A wide-impact change earns an adversarial stress-test pass
  (assumptions, failure scenarios, operational gotchas) before approval
- **Not the same as Claude Code's built-in plan mode.** That is a read-only permission mode; this
  stage is a planning discipline that can run in any mode
- For non-trivial work, decompose into phases with per-phase verifiable completion criteria

## 4. Implement

Structured execution with incremental validation and commit checkpoints.

- Validate (build/test) after each logical block using the consuming repo's own commands
- Commit after green. Small, frequent commits are save points
- If implementation diverges from the approved plan or hits unexpected complexity, stop and
  re-plan rather than pushing through a broken approach
- At phase boundaries on long work, write a save-point by invoking `/session-flow:handoff` via the Skill tool so a fresh session can resume

## 5. Test

Testing discipline: write or extend tests for the change, run the affected suite, investigate
failures to root cause.

- Never retry a failing test blindly. Reproduce, diagnose, fix, retest
- Test the change's observable behavior, not its implementation detail

## 6. Review

Quality checks before verification: self-review the diff against the consuming repo's conventions
and review criteria, or delegate to a fresh-context reviewer.

- A reviewer in a fresh context sees only the diff and the criteria, so it is not anchored by the
  reasoning that produced the change; prefer that over pure self-audit for non-trivial diffs
- For a high-stakes diff, prefer a cross-vendor advisor **when one is installed and set up**, for example the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs, with the fresh-context same-vendor subagent as the stated fallback,
  never a route to a command that may not resolve
  (per `docs/plugin-philosophy.md` "Fresh-eyes checkpoints" in the marketplace repository)

## 7. Verify outcome

Prove the change achieved its intent, with evidence.

- Mechanical pass first: build + test + lint per the consuming repo's commands
- Then outcome confirmation: does the result match the contract/plan? Exercise the affected flow,
  not just the compiler
- **Never claim improvement without before/after measurements.** Baselines first, measure deltas,
  report with data

## 8. Retrospective

Session analysis, learning codification, and trend tracking: the self-improvement loop. Invoke the
sibling `retro` skill (`/session-flow:retro`, or `/session-flow:retro quick` under context pressure).

## PR lifecycle (after step 7)

Prep (review + verify evidence) → create → monitor CI → address review findings → merge. Standalone
sequence, not a numbered stage. See `context/pre-pr.md` for the ordered gate checklist.
