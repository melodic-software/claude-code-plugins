---
name: workflow
description: "Navigate a staged development workflow (explore → research → plan → implement → test → review → verify → retro) and suggest the next stage. Use when: 'workflow', 'what step am I on', 'what comes next', 'pre-pr sequence', 'wrap up', at session start, or whenever the next step is unclear."
argument-hint: "[mode] (e.g., /workflow, /workflow steps, /workflow pre-pr, /workflow wrap-up, /workflow philosophy, /workflow spec-first)"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "not a git repository"`
Working tree: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`
Recent commits: !`git log --oneline -5 2>/dev/null || echo "no commits"`

## Purpose

The reference and navigator for a staged development workflow. Individual stages are executed by
whatever means the consuming repo provides (its own stage skills, or inline work); this skill is the
map — it defines the stages, detects the current position, and suggests what comes next.

**Three roles:**

1. **Reference** — stage definitions and how stages compose (`context/steps.md`)
2. **Navigator** — session-aware guidance on which stage comes next based on what's been done
3. **Checklist** — pre-PR sequence and end-of-session wrap-up as structured checklists

## Consumer conventions

This skill adapts to the consuming repo rather than imposing structure:

- **Stage execution.** When the consuming repo defines a skill for a stage (its skill listing or
  `CLAUDE.md` names one — e.g. an explore, research, plan/architect, or implement skill), suggest
  invoking that skill. Otherwise execute the stage inline following its definition in
  `context/steps.md`. Never invent skill names — check what actually exists.
- **Artifact location.** When persisting stage outputs or checklists, honor the consuming repo's
  documented convention for work/planning artifacts (check `.claude/topic-docs.yaml`, `CLAUDE.md` /
  `.claude/rules/`). When no convention exists, the checklist is a per-topic stage ledger at
  `<memory_dir>/<slug>/workflow-checklist.md` — default `.work/<slug>/workflow-checklist.md`, the
  topic's memory-tier slice per the plugin binding
  ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)):
  never committed; on the session's first memory-tier write, verify-or-create the resolved memory
  root's `.gitignore` containing `*` (announced). The sibling `handoff` skill's
  `<memory_dir>/handoffs/` holds only handoff save-points — a fixed-filename checklist there would
  clobber across two in-flight topics.
- **Quality gates.** The consuming repo's own build/test/lint commands and review criteria govern;
  this skill names WHERE gates belong in the sequence, not what they contain.

## Argument parsing

Parse the first argument to determine mode:

| Argument | Mode | Action |
|----------|------|--------|
| *(none)* | **Default** | Show compact stage overview + detect current position + suggest next stage |
| `steps` | **Steps** | Load `context/steps.md` — full stage definitions |
| `pre-pr` | **Pre-PR** | Load `context/pre-pr.md` — pre-PR sequence checklist |
| `wrap-up` | **Wrap-up** | Load `context/wrap-up.md` — end-of-session checklist |
| `philosophy` | **Philosophy** | Load `context/philosophy.md` — depth expectations and verification rigor |
| `spec-first` | **Spec-first** | Load `context/spec-first.md` — stage-by-stage execution with `/clear` between stages |

## Default mode (no arguments)

### 1. Show the workflow at a glance

```text
0. Contract   (optional — lock goal, constraints, acceptance criteria before building)
1. Explore  → 2. Research → 3. Plan (+ stress-test) → 4. Implement
5. Test     → 6. Review   → 7. Verify outcome       → 8. Retrospective (/retro)
PR lifecycle: prep → create → monitor CI → merge (runs after step 7)
```

### 2. Detect current position

Check conversation context for evidence of completed stages:

- Is the goal/constraints/acceptance-criteria contract crisp (stated by the user, or in a plan
  artifact on disk)? → Stage 0 satisfied
- Has the relevant code been read or the codebase surveyed? → Stage 1 done
- Have external sources been consulted for load-bearing technical claims? → Stage 2 done
- Has a plan been written and approved? → Stage 3 done
- Has code been written via Write/Edit? → Stage 4 in progress or done
- Have tests been run? → Stage 5 done
- Has a self-review or delegated review happened? → Stage 6 done
- Has the outcome been verified against intent with evidence? → Stage 7 done
- Is there a PR? → PR lifecycle in progress

Verify a stage from its artifact or output — a plan file, cited sources, green test output — not
from conversation vibes.

### 3. Suggest next stage

Based on what's been done, recommend the next stage with rationale. If the consuming repo has a
skill for that stage, name it; otherwise describe the inline work.

### 4. Track progress (tasks ≥3 stages)

For work expected to span 3+ stages, create a task per applicable stage via TaskCreate, mark
completed stages `completed` and the current one `in_progress`. For durable cross-`/clear` tracking,
also copy `templates/checklist.md` into the artifact location (see "Consumer conventions") as
`workflow-checklist.md` and tick boxes as stages produce their outputs. Skip the file when the
consuming repo already tracks the same stages in its own plan artifact — never mirror progress in
two files.

## Key principles (always apply, regardless of mode)

- **Verification rigor is size-independent** — a one-line config change gets the same rigor as a
  multi-file feature (`context/philosophy.md`)
- **This skill navigates; stages execute elsewhere** — route to the stage work once position is
  known, don't re-run it here
- **Verify stage completion from artifacts** — a stage is done when its output exists, not when it
  was mentioned

## Gotchas

- **Marking a stage done from conversation vibes** — verify the artifact or output exists before
  suggesting the next stage.
- **Skipping the contract stage on behavior-changing work** — fuzzy intent becomes silent plan
  assumptions; lock the goal and acceptance criteria first.
- **Opening a PR before the verify stage** — the pre-PR sequence (`context/pre-pr.md`) is ordered
  for a reason; verification evidence comes before the PR, not after.

## What this skill does NOT do

- **Does not execute stages** — it is the map, not the territory
- **Does not replace the consuming repo's own gates** — build/test/lint commands, review criteria,
  and commit conventions stay repo-owned
- **Does not require any specific stage skills to exist** — every stage degrades gracefully to
  inline execution
