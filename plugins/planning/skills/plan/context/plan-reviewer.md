# Plan Reviewer — Sub-Agent Dispatch

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

Read in order:
1. The consuming project's review conventions (rules / review checklists), when provided
2. The plan body provided below
3. Design artifacts or design-resolution.md when provided

Do not edit files. Attack the plan for gaps. Return a findings table only.

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
- Contract migrations have a pre-flight consumer check as the first work item

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
