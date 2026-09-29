---
description: "Apply a prior /repo-fleet-hygiene:audit action-plan JSON behind one fleet confirmation: default dry-run re-derives branch/worktree tips and prints the ordered batch; --apply mutates only after interactive confirmation or --yes. Owns batched merged-local-branch deletion with fail-closed OID refresh; cleans merged/prunable/missing worktrees in plan order (branches before worktrees). Opt-in --remote-branches adds per-branch gated deletion of never-PR and closed-unmerged remote branches. Use when: 'apply fleet plan', 'execute fleet cleanup', 'batch delete merged branches', 'one confirmation for fleet cleanup', 'delete stale remote branches'."
user-invocable: true
disable-model-invocation: true
argument-hint: "--plan-file <path> [--apply] [--yes] [--remote-branches]"
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
fleet cleanup contract. It is a separate skill from `:audit` on purpose: the audit's
`allowed-tools` grant matches any argv on `audit-fleet.sh`, so an execute flag there would widen
mutation authority silently.

Default is **dry-run** (evidence refresh + ordered preview, no mutation). Execution requires an
explicit `--apply`, then interactive confirmation **or** `--yes` for non-interactive consent.

## Non-negotiable boundary

- Never run without `--plan-file` pointing at a prior audit plan (`schema_version: 1`).
- Never treat plan tips as authorization. Re-derive every mutable OID immediately before delete.
- Skip fail-closed on OID drift, missing plan OID, protected/current/worktree-attached branches,
  locked or stranded worktrees, or unknown operations.
- Own batched `merged-local-branch` deletion here (repo-hygiene branch deletion stays interactive /
  per-repo and is not batched).
- Order: `delete-merged-local-branches`, `cleanup-worktrees`, then `delete-remote-branches`.
- Default is unchanged: no remote branch is deleted unless `--remote-branches` is passed.

## Arguments

Parse `$ARGUMENTS` and pass them through to the bundled script. Supported flags:

- `--plan-file <path>` (required): action-plan JSON from a prior audit (`--plan-file` on audit, or
  the temp path named in the audit report).
- `--apply`: opt into mutation after the batch confirmation gate.
- `--yes` / `-y`: skip the interactive prompt (required for non-interactive `--apply`).
- `--remote-branches`: opt in to `delete-remote-branches` rows (`unmerged-remote-branch` findings of
  class `never-pr` or `closed-unmerged`). Without it those rows are skipped with
  `remote deletion requires --remote-branches`, no remote is contacted, and local operations behave
  exactly as before. `--yes` never answers this flag's prompts.

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

One gate covers every repository and every local operation in the plan.

### Remote branch rows (`--remote-branches`)

Remote deletion is separate from that gate and stricter:

- Before any prompt the script re-checks each row against live state and skips on drift, a head
  already gone, or the remote's default branch. It re-reads the tip with `git ls-remote`. It requires
  every URL Git would fetch from or push to for the remote (effective config, so `pushurl` and
  `url.*.insteadOf` count) to name the repository the audit recorded in `remote_key`. It re-reads
  the branch's pull requests with `gh pr list --state all` for `github_repo`: `never-pr` needs
  none, `closed-unmerged` needs only `CLOSED` ones with one at the plan tip. An `OPEN` or `MERGED`
  pull request, a changed class, a full 100-row page, or a failed `gh` call skips the row. The
  identity and pull request checks run again after a yes and before the ledger write and the push.
- Each branch gets its own `[y/N]` prompt naming repository, remote, branch, class, and tip. `--yes`
  does not answer it. A non-interactive session with any remote row that would be prompted deletes
  nothing at all, local rows included (exit 3).
- Before each push the tip is appended to `<plan-file>.tip-ledger` (tab-separated: repository,
  remote, branch, class, tip, UTC time, restore command). A ledger write failure aborts that branch
  (exit 4). The push is `git push <remote> --delete refs/heads/<branch>` with a lease on the exact
  recorded tip, so a head that moved since the read is not deleted.
- Restore a branch by running the ledger line's last field, `git -C <repo> push <remote>
  <tip>:refs/heads/<branch>`. It works only while the tip object exists locally. Apply fetches the
  tip first when it is absent, but a successful delete removes the remote-tracking ref, so the
  object is unreachable afterward and `git gc` prunes it once `gc.pruneExpire` passes (two weeks by
  default).
- **Claim:** `gc.pruneExpire` defaults to two weeks. **Basis:** the `gc.pruneExpire` entry of
  <https://git-scm.com/docs/git-gc> ("prune --expire 2.weeks.ago"), matching `git help config`
  (git 2.53.0). **As of:** 2026-09-29. **Recheck:** when a Git release changes the
  `gc.pruneExpire` default or the restore window in that entry.
- The script prompts only when its stdin is a terminal. When it has none, `--remote-branches` only
  previews and exits 3. To delete, run `apply-plan.sh --plan-file <path> --apply --remote-branches`
  in your own terminal.

Scope is fixed by the audit: only never-PR and closed-unmerged branches are planned. Branches with a
merged PR (`merged-remote-branch`) are out of scope and are rejected if they appear in a
`delete-remote-branches` row.

## What this skill does NOT do

- Re-run fleet discovery or GitHub evidence collection. That is `/repo-fleet-hygiene:audit`.
- Add execution flags to `audit-fleet.sh`.
- Batch-delete via `/repo-hygiene:clean git` (that skill refuses to batch branch deletion).
- Remove stranded/dirty/locked worktrees, or act on tip-drift / manual-review findings.
- Change GitHub `delete_branch_on_merge`.
- Delete a remote branch without `--remote-branches`, without its own per-branch confirmation, or
  when its merged PR is the only evidence.

## Workflow

1. Operator runs `/repo-fleet-hygiene:audit … --plan-file <path>` (or takes the path from the report).
2. Review the plan: `${CLAUDE_SKILL_DIR}/scripts/apply-plan.sh --plan-file <path>`
3. Apply once: add `--apply` (interactive) or `--apply --yes` (headless). Remote branch rows need `--remote-branches` and the operator's own terminal.
4. Report failed and skipped targets first, each with its reason (a skip names the fail-closed reason: OID drift, etc.), then the applied count.
