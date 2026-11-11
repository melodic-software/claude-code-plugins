# Workflow Stages: Full Definitions

The staged development workflow, including its optional and conditional stages. When the consuming
repo defines a skill for a stage, invoke it; otherwise execute the stage inline per its definition
here. A conditional stage runs only when its trigger holds; otherwise it is skipped and marked SKIPPED, with the reason, on its checklist box.

These definitions govern the full path. A change whose diff is quick to review and cheap to retry
takes the quick-change on-ramp (SKILL.md "On-ramps") instead: it enters at stage 8, where reading
the code it needs is part of implement, and returns to stage 1 if its diff turns out not to be
quick to review. A diff that adds types, public contracts, or module boundaries is not cheap to
retry and takes the full path. New work whose diff fails either test enters at stage 1, the
interview, which calls stages 2-4 as detours when a question needs them.

**The level each stage decides.** The interview decides behavior (the Brief), design decides
interfaces and contracts, and plan decides files and symbols. A question at another stage's level
goes back to that stage rather than being settled where it surfaced.

**Effort per stage.** Each stage carries an **Effort** line naming the kind of work it is. To
advise effort for a stage, read model-config's effort table (pointer below) when giving the
advice, pick the level whose described use fits that kind of work, and name both the level and
the matched use. A stage that changes code or verifies it is never advised below medium; skip any
row the table says is not an effort level. When the page cannot be read, say so and advise no
level. The advice is the human's to act on; this skill never sets
effort.

- **Pointer**: for choosing an effort level, see
  [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level).

## 1. Interview (optional: lock the Brief before building)

Drive fuzzy intent to a zero-ambiguity Brief before behavior-changing work: goal, constraints,
acceptance criteria, captured assumptions. Persist it (a plan file in the repo's artifact location)
so later stages aim at an explicit target instead of inferring one mid-task. It decides behavior;
interfaces and contracts wait for design, files and symbols for plan.

- Trigger conditions: intent is fuzzy, scope is uncalibrated, or, on the full path, the work
  changes behavior, structure, or contracts
- Skip conditions: a change whose diff is quick to review and cheap to retry (the quick-change
  on-ramp), or follow-ups where the Brief IS the conversation
- Front-loads clarification cost in one round-trip; ask the questions the design turns on one at a
  time, highest architectural blast radius first
- Calls explore, research or a PRD (stages 2-4), or a prototype, only when a question it asks
  needs one, then resumes; none of them runs before it
- **Effort:** scoping in question rounds the human answers one at a time

## 2. Explore (conditional: a question needs the code read)

Structured local codebase exploration: read the relevant code, git history, file layout, tests, and
dependencies. Understand current state before changing anything.

- Trigger conditions: a question the interview, design, or plan asks turns on what the code does
  now
- Skip conditions: nothing in the repository bears on the question (the interview's fast survey
  answered it)
- Survey breadth-first (glob/grep), confirm the files the change touches, then read those in full
- When code, `git status` or history references a file that is not on disk, probe before any
  investigation the task did not ask for. Run
  `git --no-optional-locks status --porcelain -- <path>` and
  `git log --oneline -1 --diff-filter=D -- <path>`, each its own read-only call. A status line
  decides first; the deleting commit counts only when status prints nothing:
  - **Intentional**: a staged removal (`D` in the first status column), or no status line and a
    commit that deleted the path. Skip investigating it and say so, citing the status line or
    commit
  - **Unexplained**: deleted only in the working tree (`D` in the second status column).
    Investigate it like any other file in scope
  - **Not settled**: neither probe names the path, or a probe fails. Ask before investigating
- **Effort:** reading and surveying code with no change made

## 3. Research (conditional: a question rests on an external claim)

External verification of technical claims: official docs, primary sources, current versions.

- Trigger conditions: an answer or a later stage depends on a fact from outside the repository (a
  documented default, limit, version, or behavior)
- Skip conditions: no claim the work depends on comes from outside the repository
- No claim the work depends on is accepted without verified, current information from authoritative
  sources
- **Task size does NOT reduce research depth.** A one-line config change gets the same
  verification rigor as a multi-file feature
- Reading a document and restating its conclusions is not research. Analysis requires independent
  verification
- **Effort:** verifying technical claims against primary sources, where a wrong claim carries into
  the plan

Stages 2-4 are detours: the interview, or a later stage, calls one when a question needs it, and
the work returns to the stage that called it.

## 4. PRD (conditional: lock product intent)

Write down the problem, the users, and the success metrics when the interview finds that product
intent is unsettled, so the Brief aims at an agreed outcome.

- Trigger conditions: the change is user-facing AND business-driven AND alignment across people
  matters (a new user-facing surface, a cross-team initiative)
- Skip conditions: engineering-internal work (refactors, infrastructure, conventions, bug fixes)
- Before it, a rough problem may be diverged into candidate approaches. A too-big and still-foggy
  effort is charted into decisions only after an interview outgrows one session, and the chart
  can graduate here
- When the users themselves are unsettled (who they are, what they need), UX research and
  synthesis come before the PRD, through a user-experience capability (if installed, e.g.
  /user-experience:shape); without one, interview the human about the users inline
- **Effort:** settling product intent with the human, one open question at a time

## 5. Design

Resolve the technical design before the plan: module layout, contracts and type shapes, which axes
are designed to vary, and which existing conventions the solution follows. A gate checks that no
design thread is left unresolved and untagged, then writes the decisions into the plan artifact's
design section, which is how they reach the implementer.

- Trigger conditions: new types or contracts, a new module or library, a package-topology,
  cross-module, or data-model change, a new user-facing flow or screen. Two to five files with one
  new type is light design
- Skip conditions: a single-file bug fix, a config or doc change, a rename, a pure test addition.
  The skip is recorded as a one-line early exit with its reason, not left implicit, so the plan
  stage can see it. On the full path, size alone never skips it
- Domain modeling, prototypes, and architecture surveys feed it; a decision that passes the
  admission test of an architecture-decision capability (if installed, e.g.
  /architecture:record-decision) is recorded as an architecture decision before planning; without
  one, each decision made over a weighed alternative is listed for the human to judge whether it
  earns a record
- A user-facing flow or screen is designed before the technical design: the flow and navigation
  through a user-experience capability (if installed, e.g. /user-experience:structure), then the
  screens through an interface-design capability (if installed, e.g. /user-interface:design);
  without them, sketch the flow and screens inline
- **Effort:** settling contracts and boundaries with the human, where a wrong boundary is paid for
  in every later phase

## 6. Plan

Structured plan with rationale, test strategy, and a user approval gate before execution begins.

- Include what will change, why, in what order, and how success is verified
- Plan depth scales to blast radius. A wide-impact change earns an adversarial stress-test pass
  (assumptions, failure scenarios, operational gotchas) before approval
- **Not the same as Claude Code's built-in plan mode.** That is a permission mode (pointer:
  <https://code.claude.com/docs/en/permission-modes#analyze-before-you-edit-with-plan-mode>); this stage is a planning
  discipline that can run in any mode
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
- A closed wayfind map whose destination is a set of build items enters here directly, past
  design and plan: its resolved decisions stand in for them (owner decision Q531, #12477)
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
and review criteria as the floor, then delegate to a fresh-context reviewer. The stage is done only
when that reviewer has returned, unless the `verification` level is `light` or `off`
(`context/pre-pr.md` step 2). Resolve the level first if this session has not, as `SKILL.md`
("The verification level") says, on this route too.

- The fresh-context reviewer, not the author, closes the stage, because the author's reasoning
  cannot color what that reviewer concludes
  - **Pointer**: for the review-against-your-spec step, see
    [Review against your spec](https://code.claude.com/docs/en/best-practices#review-against-your-spec)
- For a high-stakes diff, prefer a cross-vendor advisor **when one is installed and set up**, for example the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs, with the fresh-context same-vendor subagent as the stated fallback (this preference is this repository's judgment, not an upstream rule),
  never a route to a command that may not resolve
  (per `docs/plugin-philosophy.md` "Fresh-eyes checkpoints" in the marketplace repository)
- A diff that changes a user interface also gets an interface review through an interface-review
  capability (if installed, e.g. /user-interface:audit); without one, the code review covers it
- **Effort:** judging a diff for defects, where a missed defect ships

## 11. Verify outcome

Prove the change achieved its intent, with evidence.

- Mechanical pass first: build + test + lint per the consuming repo's commands
- Then outcome confirmation: does the result match the Brief and plan? Exercise the affected flow,
  not just the compiler. The verdict comes from a fresh-context verifier, not the author
  (an outcome-verification capability, if installed, e.g. /verification:confirm, dispatches one
  at the level it reads; without one, dispatch the verifier with the Brief and the diff, except
  under this skill's `light` or `off` level (Stage 10), where the report notes
  `verification: skipped (<level>)`)
- **Never claim improvement without before/after measurements.** Baselines first, measure deltas,
  report with data
- **Effort:** proving the outcome with evidence before the work is called done

## 12. Retrospective (optional)

Session analysis and learning codification: the self-improvement loop. Invoke the sibling `retro`
skill (`/session-flow:retro`, or `/session-flow:retro quick` under context pressure). Score trends
across sessions are `/session-flow:audit-sessions trends`.

- **Effort:** reviewing the session's own record, every finding going to the human to accept or
  reject

## Ship: PR lifecycle (after stage 11)

Prep (review + verify evidence) → create → monitor CI → address review findings → merge. Standalone
sequence, not a numbered stage. See `context/pre-pr.md` for the ordered gate checklist.
