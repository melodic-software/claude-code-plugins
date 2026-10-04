# Workflow Stages: Full Definitions

The staged development workflow, including its optional and conditional stages. When the consuming
repo defines a skill for a stage, invoke it; otherwise execute the stage inline per its definition
here. A conditional stage runs only when its trigger holds; otherwise it is skipped and marked SKIPPED, with the reason, on its checklist box.

**Effort per stage.** Each stage carries an **Effort** line naming the kind of work it is. To
advise effort for a stage, read model-config's effort table (pointer below) when giving the
advice, pick the level whose described use fits that kind of work, and name both the level and
the matched use. A stage that changes code or verifies it is never advised below medium; skip any
row the table says is not an effort level. When the page cannot be read, say so and advise no
level. The advice is the human's to act on; this skill never sets
effort.

- **Pointer**: for choosing an effort level, see
  [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level).
- **As of**: 2026-10-02
- **Recheck trigger**: the section is renamed or moved, or its table columns change.

## 1. Explore

Structured local codebase exploration: read the relevant code, git history, file layout, tests, and
dependencies. Understand current state before changing anything.

- Survey breadth-first (glob/grep), confirm the files the change touches, then read those in full
- When files referenced in git status or history don't exist on disk, ask before investigating.
  They may be intentionally deleted
- **Effort:** reading and surveying code with no change made

## 2. Research

External verification of technical claims: official docs, primary sources, current versions.

- No claim the work depends on is accepted without verified, current information from authoritative
  sources
- **Task size does NOT reduce research depth.** A one-line config change gets the same
  verification rigor as a multi-file feature
- Reading a document and restating its conclusions is not research. Analysis requires independent
  verification
- **Effort:** verifying technical claims against primary sources, where a wrong claim carries into
  the plan

Discover (stages 1-2) and shape (stages 3-4) interleave: a contract locked first gives explore and
research their scope, and either may run again after it.

## 3. PRD (conditional: lock product intent)

Write down the problem, the users, and the success metrics before the engineering contract, so the
contract aims at an agreed outcome.

- Trigger conditions: the change is user-facing AND business-driven AND alignment across people
  matters (a new user-facing surface, a cross-team initiative)
- Skip conditions: engineering-internal work (refactors, infrastructure, conventions, bug fixes)
- Before it, a too-big and still-foggy effort is charted into decisions first, and a rough problem
  is diverged into candidate approaches; both are optional
- **Effort:** settling product intent with the human, one open question at a time

## 4. Contract (optional: lock the brief before building)

Drive fuzzy intent to a zero-ambiguity contract before behavior-changing work: goal, constraints,
acceptance criteria, captured assumptions. Persist it (a plan file in the repo's artifact location)
so later stages aim at an explicit target instead of inferring one mid-task.

- Trigger conditions: intent is fuzzy, scope is uncalibrated, or the work changes behavior,
  structure, or contracts
- Skip conditions: one-line bug fixes, or follow-ups where the contract IS the conversation
- Front-loads clarification cost in one round-trip; ask the questions the design turns on one at a
  time, highest architectural blast radius first
- **Effort:** scoping in question rounds the human answers one at a time

## 5. Design

Resolve the technical design before the plan: module layout, contracts and type shapes, which axes
are designed to vary, and which existing conventions the solution follows. A gate checks that no
design thread is left unresolved and untagged, then writes the decisions into the plan artifact's
design section, which is how they reach the implementer.

- Trigger conditions: new types or contracts, a new module or library, a package-topology,
  cross-module, or data-model change. Two to five files with one new type is light design
- Skip conditions: a single-file bug fix, a config or doc change, a rename, a pure test addition.
  The skip is recorded as a one-line early exit with its reason, not left implicit, so the plan
  stage can see it. Size alone never skips it
- Domain modeling, prototypes, and architecture surveys feed it; a decision that is hard to
  reverse, surprising without context, and the result of a real trade-off is recorded as an
  architecture decision before planning
- **Effort:** settling contracts and boundaries with the human, where a wrong boundary is paid for
  in every later phase

## 6. Plan

Structured plan with rationale, test strategy, and a user approval gate before execution begins.

- Include what will change, why, in what order, and how success is verified
- Plan depth scales to blast radius. A wide-impact change earns an adversarial stress-test pass
  (assumptions, failure scenarios, operational gotchas) before approval
- **Not the same as Claude Code's built-in plan mode.** That is a read-only permission mode; this
  stage is a planning discipline that can run in any mode
- For non-trivial work, decompose into phases with per-phase verifiable completion criteria
- The plan keeps the design section as the design stage wrote it; each phase names the part it
  implements, and a phase that must depart from it goes back to the design stage
- **Effort:** design decisions and failure scenarios settled before any code changes, matched at
  the depth the blast radius sets for the plan

## 7. Decompose (conditional: split the plan into tickets)

Break the approved plan into independently grabbable vertical-slice work items, each sized to one
fresh session, published blockers first with dependency edges. Each item quotes the part of the
plan's design section it touches, so an agent that picks it up cold still builds to the design.

- Trigger conditions: the plan holds more than one independently shippable ticket, or the work
  will be picked up across sessions or by more than one person or agent
- Skip conditions: the plan is one ticket; implement it directly
- **Effort:** cutting the plan along its seams, where a thick slice stalls the agent that picks it
  up

## 8. Implement

Structured execution with incremental validation and commit checkpoints.

- Validate (build/test) after each logical block using the consuming repo's own commands
- Commit after green. Small, frequent commits are save points
- If implementation diverges from the approved plan or hits unexpected complexity, stop and
  re-plan rather than pushing through a broken approach
- At phase boundaries, route the continuation with the skill's default-mode section 4 (`context/continuation.md`)
- **Effort:** code-changing work within the scope the plan fixed

## 9. Test

Testing discipline: write or extend tests for the change, run the affected suite, investigate
failures to root cause.

- Never retry a failing test blindly. Reproduce, diagnose, fix, retest
- Test the change's observable behavior, not its implementation detail
- **Effort:** writing tests and diagnosing failures to root cause, where a missed case lets a
  regression through

## 10. Review

Quality checks before verification: self-review the diff against the consuming repo's conventions
and review criteria, or delegate to a fresh-context reviewer.

- A reviewer in a fresh context sees only the diff and the criteria, so it is not anchored by the
  reasoning that produced the change; prefer that over pure self-audit for non-trivial diffs
- For a high-stakes diff, prefer a cross-vendor advisor **when one is installed and set up**, for example the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs, with the fresh-context same-vendor subagent as the stated fallback,
  never a route to a command that may not resolve
  (per `docs/plugin-philosophy.md` "Fresh-eyes checkpoints" in the marketplace repository)
- **Effort:** judging a diff for defects, where a missed defect ships

## 11. Verify outcome

Prove the change achieved its intent, with evidence.

- Mechanical pass first: build + test + lint per the consuming repo's commands
- Then outcome confirmation: does the result match the contract/plan? Exercise the affected flow,
  not just the compiler
- **Never claim improvement without before/after measurements.** Baselines first, measure deltas,
  report with data
- **Effort:** proving the outcome with evidence before the work is called done

## 12. Retrospective (optional)

Session analysis, learning codification, and trend tracking: the self-improvement loop. Invoke the
sibling `retro` skill (`/session-flow:retro`, or `/session-flow:retro quick` under context pressure).

- **Effort:** reviewing the session's own record, every finding going to the human to accept or
  reject

## Ship: PR lifecycle (after stage 11)

Prep (review + verify evidence) → create → monitor CI → address review findings → merge. Standalone
sequence, not a numbered stage. See `context/pre-pr.md` for the ordered gate checklist.
