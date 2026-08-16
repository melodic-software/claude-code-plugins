---
description: "Apply a prior /repo-fleet-hygiene:audit action-plan JSON behind one fleet confirmation: default dry-run re-derives branch/worktree tips and prints the ordered batch; --apply mutates only after interactive confirmation or --yes. Owns batched merged-local-branch deletion with fail-closed OID refresh; cleans merged/prunable/missing worktrees in plan order (branches before worktrees). Use when: 'apply fleet plan', 'execute fleet cleanup', 'batch delete merged branches', 'one confirmation for fleet cleanup'."
user-invocable: true
disable-model-invocation: true
argument-hint: "--plan-file <path> [--apply] [--yes]"
allowed-tools:
  - Bash(${CLAUDE_SKILL_DIR}/scripts/apply-plan.sh:*)
metadata:
  workflow-stage: operator
  summary: Execute a fleet action plan behind one confirmation gate
  cadence: weekly
---

## Purpose

Consume the machine-readable action-plan JSON emitted by `/repo-fleet-hygiene:audit` and drive
cleanup for N repositories behind **one** confirmation gate. This is the executing verb for the
fleet cleanup contract (#2597 / #2609). It is a separate skill from `:audit` on purpose: the audit's
`allowed-tools` grant matches any argv on `audit-fleet.sh`, so an execute flag there would widen
mutation authority silently.

Default is **dry-run** (evidence refresh + ordered preview, no mutation). Execution requires an
explicit `--apply`, then interactive confirmation **or** `--yes` for non-interactive consent.

## Non-negotiable boundary

- Never run without `--plan-file` pointing at a prior audit plan (`schema_version: 1`).
- Never treat plan tips as authorization — re-derive every mutable OID immediately before delete.
- Skip fail-closed on OID drift, missing plan OID, protected/current/worktree-attached branches,
  locked or stranded worktrees, or unknown operations.
- Own batched `merged-local-branch` deletion here (repo-hygiene branch deletion stays interactive /
  per-repo and is not batched).
- Order: `delete-merged-local-branches` before `cleanup-worktrees`.

## Arguments

Parse `$ARGUMENTS` and pass them through to the bundled script. Supported flags:

- `--plan-file <path>` (required): action-plan JSON from a prior audit (`--plan-file` on audit, or
  the temp path named in the audit report).
- `--apply`: opt into mutation after the batch confirmation gate.
- `--yes` / `-y`: skip the interactive prompt (required for non-interactive `--apply`).

Reject any other flag. Run exactly once:

```bash
${CLAUDE_SKILL_DIR}/scripts/apply-plan.sh <validated-and-quoted-arguments>
```

## Confirmation gate

| Session | Flags | Behavior |
|---|---|---|
| Any | (default / no `--apply`) | Dry-run preview only |
| Interactive tty | `--apply` | Prompt once for the whole plan; decline → mutate nothing |
| Interactive tty | `--apply --yes` | Apply without prompt |
| Non-interactive | `--apply` without `--yes` | Print plan, stop (exit 3), mutate nothing |
| Non-interactive | `--apply --yes` | Apply |

One gate covers every repository and every operation in the plan.

## What this skill does NOT do

- Re-run fleet discovery or GitHub evidence collection — that is `/repo-fleet-hygiene:audit`.
- Add execution flags to `audit-fleet.sh`.
- Batch-delete via `/repo-hygiene:clean git` (that skill refuses to batch branch deletion).
- Remove stranded/dirty/locked worktrees, or act on tip-drift / manual-review findings.
- Change GitHub `delete_branch_on_merge` or delete remote branches.

## Workflow

1. Operator runs `/repo-fleet-hygiene:audit … --plan-file <path>` (or takes the path from the report).
2. Review the plan: `${CLAUDE_SKILL_DIR}/scripts/apply-plan.sh --plan-file <path>`
3. Apply once: add `--apply` (interactive) or `--apply --yes` (headless).
4. Report applied / skipped / failed counts; skips name the fail-closed reason (OID drift, etc.).
