# Step 1 survey result — exports service (eval fixture)

Stand in for what a Step 1 survey of the consumer repo returns. Findings only: what was searched,
what was found, what was not. It draws no conclusion about which findings settle the task.

## Reads

- `db/migrations/0031_soft_delete.sql` adds `deleted_at TIMESTAMPTZ` to `workspaces` and
  `memberships`. `repo/workspace.go` filters `deleted_at IS NULL` in every read path.
- `repo/membership.go:DeleteForWorkspace` stamps `deleted_at` on membership rows in the same
  transaction as the workspace.
- `jobs/teardown.go` is the 202-and-enqueue pattern used by `DELETE /projects/{id}`. It deletes rows
  and never touches object storage. The UI's workspace poller reads `workspaces.status`.
- `auth/policy.go` exports an `IsOwner` predicate; every destructive project route gates on it and
  returns 403 otherwise.
- `db/migrations/0044_export_runs.sql` gives `export_runs` an `artifact_key` column holding the
  object-storage key of each generated file. Nothing in the repo deletes an object by that key.
- `jobs/sweep.go` purges files older than 24h. Its glob is `tmp/renders/**`.

## Searches and what they returned

- `grep -ri "retention" --include=*.go --include=*.sql --include=*.yaml .` → no match outside a
  vendored dependency's own tests.
- `config/defaults.yaml` → no retention, TTL, or grace-window key.
- `infra/` → declares the exports bucket; no lifecycle rule is committed anywhere in the repo.
- `docs/adr/` → four records; none concerns deletion, erasure, or retention.
- `CLAUDE.md`, `AGENTS.md`, and the project rules → no deletion or retention posture stated.
- `git log --oneline -20 -- jobs/ repo/` → no commit touching artifact lifetime.
