# Workflow Stages — Full Definitions

The staged development workflow plus the optional contract stage. When the consuming repo defines a
skill for a stage, invoke it; otherwise execute the stage inline per its definition here.

## 0. Contract (optional — lock the brief before building)

Drive fuzzy intent to a zero-ambiguity contract before behavior-changing work: goal, constraints,
acceptance criteria, captured assumptions. Persist it (a plan file in the repo's artifact location)
so later stages aim at an explicit target instead of inferring one mid-task.

- Trigger conditions: intent is fuzzy, scope is uncalibrated, or the work changes behavior,
  structure, or contracts
- Skip conditions: one-line bug fixes, or follow-ups where the contract IS the conversation
- Front-loads clarification cost in one round-trip; ask load-bearing questions one at a time,
  highest architectural blast radius first

## 1. Explore

Structured local codebase exploration: read the relevant code, git history, file layout, tests, and
dependencies. Understand current state before changing anything.

- Survey breadth-first (glob/grep), confirm the load-bearing files, then read those in full
- When files referenced in git status or history don't exist on disk, ask before investigating —
  they may be intentionally deleted

## 2. Research

External verification of technical claims: official docs, primary sources, current versions.

- No load-bearing claim accepted without verified, current information from authoritative sources
- **Task size does NOT reduce research depth** — a one-line config change gets the same
  verification rigor as a multi-file feature
- Reading a document and restating its conclusions is not research — analysis requires independent
  verification

## 3. Plan

Structured plan with rationale, test strategy, and a user approval gate before execution begins.

- Include what will change, why, in what order, and how success is verified
- Plan depth scales to blast radius — a wide-impact change earns an adversarial stress-test pass
  (assumptions, failure scenarios, operational gotchas) before approval
- **Not the same as Claude Code's built-in plan mode** — that is a read-only permission mode; this
  stage is a planning discipline that can run in any mode
- For non-trivial work, decompose into phases with per-phase verifiable completion criteria

## 4. Implement

Structured execution with incremental validation and commit checkpoints.

- Validate (build/test) after each logical block using the consuming repo's own commands
- Commit after green — small, frequent commits are save points
- If implementation diverges from the approved plan or hits unexpected complexity, stop and
  re-plan rather than pushing through a broken approach
- At phase boundaries on long work, write a save-point (`/handoff`) so a fresh session can resume

## 5. Test

Testing discipline: write or extend tests for the change, run the affected suite, investigate
failures to root cause.

- Never retry a failing test blindly — reproduce, diagnose, fix, retest
- Test the change's observable behavior, not its implementation detail

## 6. Review

Quality checks before verification: self-review the diff against the consuming repo's conventions
and review criteria, or delegate to a fresh-context reviewer.

- A reviewer in a fresh context sees only the diff and the criteria — it is not anchored by the
  reasoning that produced the change; prefer that over pure self-audit for non-trivial diffs
- For a high-stakes diff, prefer a cross-vendor reviewer when one is installed — e.g. the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs — with the fresh-context same-vendor subagent as the fallback,
  never a route to a command that may not resolve

## 7. Verify outcome

Prove the change achieved its intent, with evidence.

- Mechanical pass first: build + test + lint per the consuming repo's commands
- Then outcome confirmation: does the result match the contract/plan? Exercise the affected flow,
  not just the compiler
- **Never claim improvement without before/after measurements** — baselines first, measure deltas,
  report with data

## 8. Retrospective

Session analysis, learning codification, trend tracking — the self-improvement loop. Invoke the
sibling `retro` skill (`/retro`, or `/retro quick` under context pressure).

## PR lifecycle (after step 7)

Prep (review + verify evidence) → create → monitor CI → address review findings → merge. Standalone
sequence, not a numbered stage — see `context/pre-pr.md` for the ordered gate checklist.
