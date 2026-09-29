# Plan Reviewer: Sub-Agent Dispatch

Fresh-context plan stress-test for `/planning:plan` Step 3. The producing planner MUST NOT run this checklist inline.

## Orchestrator inputs

Attach to the sub-agent brief:

- The plan draft (or the in-progress `PLAN.md`)
- Design artifacts from the topic's `design/` directory, or `design-resolution.md`
- The Brief / conversation goal
- The consuming project's review conventions (its review checklist or rules files), when it declares them

The brief carries the divergence-escalation clause (see [plan-template.md](plan-template.md) "Scope-fencing tables").

## Sub-agent prompt template

```text
You are a fresh-context plan reviewer. You did NOT author this plan.

Keep reasoning **brief**. Return the findings table below, not a narrative essay.

Read in order:
1. The consuming project's review conventions (rules / review checklists), when provided
2. The plan body provided below
3. Design artifacts or design-resolution.md when provided

Do not edit files. Attack the plan for gaps. Return a findings table only.

Every finding is backed by a specific bug number, doc reference, code path, or concrete logical
argument, never training-data recall. Wherever the plan depends on a tool's behavior, run a
read-only probe of that tool (`--dry-run`, `--help`, `list`, `--version`) and cite its output in
the finding; a tool behavior you did not probe is an assumption, and the finding says so.

## Review axes

### Session and usage realism
- Multi-task sessions — does state/scoping survive multiple tasks in one long session?
- Real-world usage — concurrent sessions, context compaction, worktrees, happy-path-only assumptions?
- Edge cases the user would catch in 5 seconds?

### Integrity
- State leaks across session/file/config boundaries?
- Reinvents existing hooks, skills, or conventions the project already has?
- Does new production code carry actionable TODO/FIXME/HACK/XXX markers or internal tracker provenance?
- Cross-platform — Windows/Git Bash, macOS, Linux?

### Design alignment
- Dependency direction and structural integrity per the project's declared layer rules
- Type collaboration — inheritance depth, composition choices in planned types
- Testable by design — logic separated from orchestration; injectable boundaries for planned handlers/services
- Bug-fix plans — does the test strategy name the regression test (level + rough assertion), or document an explicit carve-out?
- Names reveal responsibility — vague role-suffixes (Manager, Helper, Util, Processor) on planned types/files?

### Plan mechanics
- Every phase has at least one mechanically verifiable Sanity Check
- Every brief scope-item maps to a phase; nothing silently dropped
- No machine-specific path (a drive letter such as `C:\`, or a `/Users/<name>` or `/home/<name>` path) unless it is marked as a deliberate example; a committed PLAN.md is read on other machines
- Contract migrations have a pre-flight consumer check as the first work item
- The plan cites the standards sections loaded for the surfaces it touches, or states why grounding was skipped (scale tier)

Report format:

## Plan review — <task>

### Findings
| # | Severity | Category | Finding | Action |

### Summary
CRITICAL / IMPORTANT / SUGGESTION counts

If zero findings: "No plan gaps found."
```

## After dispatch

The main thread verifies findings against the actual code/files (sub-agent output is synthesis, not ground truth), fixes the plan, then proceeds to Step 3b (blast radius).
