---
description: "Navigate a staged workflow (explore, research, design, plan, implement, test, review, verify, retro): suggest the next stage and route the end-of-phase continuation (continue, clear, handoff, background, clean-stop, compact). Use when: 'workflow', 'what step am I on', 'what comes next', 'pre-pr sequence', 'wrap up', 'how should I continue', 'clear or compact', at session start or a phase boundary, or when the next step is unclear. For a ranked menu of every fitting skill, use /session-flow:show-options."
argument-hint: "[steps|pre-pr|wrap-up|philosophy|spec-first|continue [auto]]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Navigate the staged dev workflow and suggest the next stage
---

**Arguments.** `[steps|pre-pr|wrap-up|philosophy|spec-first|continue [auto]]`. e.g., /workflow, /workflow steps, /workflow pre-pr, /workflow wrap-up, /workflow philosophy, /workflow spec-first, /workflow continue, /workflow continue auto

## Repository context. Gather first

Take `branch`, `status`, and `recent-commits` at `-5`. No session id, this skill stamps no ledger.
Probe commands, the one-command-per-call and treat-failure-as-unknown rules, and the `$`-expansion
rationale for gathering at run time rather than pre-computing:
[`${CLAUDE_PLUGIN_ROOT}/reference/gather.md`](${CLAUDE_PLUGIN_ROOT}/reference/gather.md).

## Purpose

The reference and navigator for a staged development workflow. Individual stages are executed by
whatever means the consuming repo provides (its own stage skills, or inline work); this skill is the
map. It defines the stages, detects the current position, and suggests what comes next.

**Three roles:**

1. **Reference**, stage definitions and how stages compose (`context/steps.md`)
2. **Navigator**, session-aware guidance on which stage comes next based on what's been done
3. **Checklist**. Pre-PR sequence and end-of-session wrap-up as structured checklists

## Consumer conventions

This skill adapts to the consuming repo rather than imposing structure:

- **Stage execution.** When the consuming repo defines a skill for a stage (its skill listing or
  `CLAUDE.md` names one, e.g. an explore, research, plan, or implement skill), suggest
  invoking that skill. Otherwise execute the stage inline following its definition in
  `context/steps.md`. Never invent skill names. Check what actually exists.
- **Artifact location.** When persisting stage outputs or checklists, honor the consuming repo's
  documented convention for work/planning artifacts (check `CLAUDE.md` /
  `.claude/rules/`). When no convention exists, the checklist is a per-topic stage ledger at
  `<memory_dir>/<slug>/workflow-checklist.md`. Default `.work/<slug>/workflow-checklist.md`, the
  topic's memory-tier slice:
  never committed; on the session's first memory-tier write, verify-or-create the resolved memory
  root's `.gitignore` containing `*` (announced). The sibling `handoff` skill's
  `<memory_dir>/handoffs/` holds only handoff save-points, a fixed-filename checklist there would
  clobber across two in-flight topics.
- **Quality gates.** The consuming repo's own build/test/lint commands and review criteria govern;
  this skill names WHERE gates belong in the sequence, not what they contain.
- **Override boundary.** The stage set itself is fixed. Plugin identity, not consumer config; there
  is no seam to swap in a different taxonomy, and this skill never reads a consumer-supplied one.
  What adapts flows through the conventions above (execution routes to your skills; gate commands
  and review criteria come from your repo), never by editing the plugin.

## Argument parsing

Read `$ARGUMENTS` whole: its first word is the mode and, when the mode is `continue`, its second word is the continuation modifier. Treat a missing mode as the default row. Treat a missing modifier, or any modifier other than `auto`, as suggest-only continuation. `auto` is the only modifier.

| Argument | Mode | Action |
|----------|------|--------|
| *(none)* | **Default** | Show compact stage overview + detect current position + suggest next stage |
| `steps` | **Steps** | Load `context/steps.md`, full stage definitions |
| `pre-pr` | **Pre-PR** | Load `context/pre-pr.md`, pre-PR sequence checklist |
| `wrap-up` | **Wrap-up** | Load `context/wrap-up.md`, end-of-session checklist |
| `philosophy` | **Philosophy** | Load `context/philosophy.md`, depth expectations and verification rigor |
| `spec-first` | **Spec-first** | Load `context/spec-first.md`, stage-by-stage execution from a written spec |
| `continue` | **Continuation** | Load `context/continuation.md`, end-of-phase continuation-mechanism router; recommend one mechanism, do not execute it |
| `continue auto` | **Continuation (autonomous)** | The `continue` mode plus its one modifier. Consume the second token before dispatching, or this row is unreachable and `auto` silently degrades to suggest-only. Same router, plus the per-invocation license to EXECUTE the mechanism it routes to. Authorizes this invocation only, never a standing mode, and never a substitute for a routed skill's own hard gate |

## Default mode (no arguments)

### 1. Show the workflow at a glance

```text
Discover:  1. Explore → 2. Research
Shape:     3. PRD (conditional) → 4. Contract (optional)
Build:     5. Design → 6. Plan (+ stress-test) → 7. Decompose (conditional) → 8. Implement
Check:     9. Test → 10. Review → 11. Verify outcome
Ship:      PR lifecycle: prep → create → monitor CI → merge (runs after stage 11)
12. Retrospective (optional, /session-flow:retro)
```

Conditional stages run only on their trigger (`context/steps.md`): PRD for a user-facing,
business-driven change where alignment on the problem matters; Decompose when the plan holds more
than one independently shippable ticket. Design runs for design-significant work and records a
one-line early exit otherwise, so a bug fix passes through it in one step. Discover and shape
interleave: on new work that does not qualify as a quick change, the contract interview runs
first and gives explore and research their scope, as detours it triggers.

Stages 1-7 expand, for unfamiliar territory, into a known pre-implementation order (blindspot →
brainstorm/prototype → PRD → interview, escalating to wayfind when it outgrows one session →
reference port → design → plan → decompose); the workflow section of
`docs/finding-your-unknowns.md` in the marketplace repository states it with rationale.

### 2. Detect current position

Check conversation context for evidence of completed stages:

- Has the relevant code been read or the codebase surveyed? → Stage 1 done
- Have external sources been consulted for load-bearing technical claims? → Stage 2 done
- Is product intent (problem, users, success metrics) written down, or is the work not
  user-facing and business-driven? → Stage 3 satisfied
- Is the goal/constraints/acceptance-criteria contract crisp (stated by the user, or in a plan
  artifact on disk)? → Stage 4 satisfied
- Does the plan artifact carry its design section, or a recorded early exit? → Stage 5 done
- Has a plan been written and approved? → Stage 6 done
- Is the plan one ticket, or have its tickets been published? → Stage 7 satisfied
- Has code been written via Write/Edit? → Stage 8 in progress or done
- Have tests been run? → Stage 9 done
- Has a self-review or delegated review happened? → Stage 10 done
- Has the outcome been verified against intent with evidence? → Stage 11 done
- Is there a PR? → PR lifecycle in progress

Verify a stage from its artifact or output, a plan file, cited sources, green test output, not
from conversation vibes.

A session that began at an entry skill (explore, research, blindspot, brainstorm, debug, triage,
an interview) is placed on the ladder by the same evidence: credit the stages its output
satisfies, then continue from there.

### 3. Suggest next stage

Based on what's been done, recommend the next stage with rationale. For new work whose diff fails
either quick-change test, with nothing done, suggest the contract interview (stage 4, after stage
3 when the PRD trigger holds), not stage 1; explore and research then run as detours the
interview triggers. This fresh-start suggestion takes precedence over tie-break rule 3 ("the
earlier stage wins"). A change that passes both tests takes the quick-change on-ramp below
instead. If the consuming repo has a
skill for that stage, name it; otherwise describe the inline work. Add that stage's effort advice per "Effort per stage" in `context/steps.md`.

### 4. Route the continuation mechanism at a phase boundary

When the just-finished work closed out a stage (its artifact exists), or the user is asking how
to carry on, the *mechanism* question is separate from the *next stage* question: continue here,
`/clear`, handoff, background, clean-stop, or compact. Load `context/continuation.md` and walk
its ordered router; recommend exactly one mechanism with its rationale, zone-informed when
context-guard's zone report (its `mcp__context-guard__status` tool, or its snapshot) has data and
conservative when it does not. Mid-stage with a healthy window,
skip this, the default is simply to continue. Mid-stage with a bloated window, walk the router
too.

The router **suggests; it does not act**. The recommendation goes to the human with the evidence
that drove it, and executing the routed mechanism takes an explicit per-invocation license
(`continue auto`, or the user's own words), which expires with the invocation. Its inputs beyond
the gather above are presence-gated pointers to the siblings that own them; the rules live there.

### 5. Track progress (tasks ≥3 stages)

For work expected to span 3+ stages, when this session has the task tools (`TaskCreate` is in its
tool list; branch on that, never on the model), create a task per applicable stage via TaskCreate,
mark completed stages `completed` and the current one `in_progress`. With `TodoWrite` instead,
keep the same stage list in `TodoWrite`. With neither, the checklist
file below (or the plan artifact that replaces it) is the only progress tracker. For durable
cross-`/clear` tracking,
also copy `templates/checklist.md` into the artifact location (see "Consumer conventions") as
`workflow-checklist.md` and tick boxes as stages produce their outputs. Skip the file when the
consuming repo already tracks the same stages in its own plan artifact, never mirror progress in
two files.

Which sessions get the task tools is an upstream default we do not restate.

- **Pointer**: when deciding whether this session has the task tools, fetch
  [Task tool availability](https://code.claude.com/docs/en/tools-reference#task-tool-availability)
  live.
- **As of**: 2026-10-10
- **Recheck trigger**: that section changes which sessions, models, or opt-ins get the task tools.

## On-ramps: work that merges into the flow partway

The stage sequence is the main line, not the only entrance. Work also arrives from the side and
merges in at a later stage. Recognize the CLASS of arrival and merge at the right point instead of
forcing every session through stage 1. Common classes:

- **A quick change**, one whose diff will be quick to review and cheap to retry. Those two tests
  decide, not size; a diff that adds types, public contracts, or module boundaries is not cheap
  to retry and takes the full path. It enters at stage 8 (reading the code it needs is part of
  implement), then the diff is reviewed and aligned on there, with test and verify at full
  rigor. If the diff turns out not to be quick to review, stop and route to the contract
  interview. Basis for adopting this rule:
  the "Session-start flow and main flow" section of `docs/upstream/mattpocock-skills-v12-map.md`
  in the marketplace repository.
- **Incoming bug or issue intake**, a report or request that arrived raw from outside. An
  already-diagnosed, agent-ready item merges at implement; observed-but-undiagnosed breakage routes
  through a diagnosis capability first (if the consuming setup installs one, e.g. from a diagnose
  or debugging plugin), then rejoins at implement with the root cause in hand.
- **A foggy, too-big-to-plan effort**, the destination is clear but the route is not, and no
  single plan can hold it yet. Start at the contract interview anyway; when that interview
  outgrows one session, escalate to a wayfinding or route-charting capability (if installed, e.g.
  from a planning plugin), which converts the remaining unknowns into decisions BEFORE the plan
  stage. Never start there. Without one, run explore/research cycles until a plan becomes
  writable.
- **Codebase-upkeep findings**. Audits, tidy sweeps, and architecture surveys surface candidate
  improvements rather than mid-flight work. Each finding the user picks up is a NEW idea entering a
  fresh cycle at contract/explore; it never merges into an in-progress cycle's later stages.

These are classes, not an inventory. Match the arriving situation to its class, then check what the
consuming setup actually installs for that class, the same rule as stage execution: never invent
skill names, and degrade to inline work when nothing is installed.

## When two capabilities both fit

Adjacent capabilities overlap at their edges. Intake vs diagnosis, wayfinding vs planning, upkeep
vs review. Route to exactly ONE owner and state why; never present both and leave the user to
disambiguate. Precedence:

1. **Exclusion language wins.** A capability whose own description disclaims the situation ("skip
   when", "not for") is out, however well its trigger words match.
2. **The more specific claim owns it.** Observed broken behavior belongs to diagnosis, not a
   generic implement pass; a route-finding problem belongs to wayfinding, not an oversized plan.
3. **Still tied → the earlier stage wins**, every downstream stage remains reachable from it, but
   a skipped upstream stage is gone.

**This rule governs STAGE routing, not option surfacing.** "Never present both" is about refusing to
hand the user two candidate owners for one stage decision and letting them sort it out. It is not a
prohibition on ever showing a set: deliberately laying out the whole option set, ranked and
annotated, for a human to choose from is a different job, and `/session-flow:show-options` owns it.
Reach for this skill when the user wants the next stage decided; reach for that one when they want
the menu. The two are complementary, not competing, and when a request could be either, "what comes
next" is a stage question and belongs here.

## Key principles (always apply, regardless of mode)

- **Verification rigor is size-independent**. A one-line config change gets the same rigor as a
  multi-file feature (`context/philosophy.md`)
- **This skill navigates; stages execute elsewhere**. Route to the stage work once position is
  known, don't re-run it here
- **Verify stage completion from artifacts**. A stage is done when its output exists, not when it
  was mentioned

## Gotchas

- **Marking a stage done from conversation vibes**. Verify the artifact or output exists before
  suggesting the next stage.
- **Skipping the contract stage on behavior-changing work that takes the full path**. Fuzzy
  intent becomes silent plan assumptions; lock the goal and acceptance criteria first. Only the
  quick-change on-ramp skips it, and only while its diff stays quick to review.
- **Skipping design because the task is small**. Size does not decide it: on the full path, new
  types, contracts, or module boundaries go through the design stage, or the implementer gets no
  design guardrails.
- **Opening a PR before the verify stage**, the pre-PR sequence (`context/pre-pr.md`) is ordered
  for a reason; verification evidence comes before the PR, not after.
- **Routing from a stale map**, a navigator that has drifted from the actual capability inventory
  is worse than none: it confidently routes to things that were renamed or removed. Whenever
  capabilities are added, renamed, or retired, in the consuming setup or in this marketplace,
  re-check that the flows described here still match what exists before trusting a route.

## What this skill does NOT do

- **Does not execute stages**; it is the map, not the territory
- **Does not replace the consuming repo's own gates**, build/test/lint commands, review criteria,
  and commit conventions stay repo-owned
- **Does not require any specific stage skills to exist**, every stage degrades gracefully to
  inline execution
