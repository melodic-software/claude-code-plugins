# Plugin data reports — keying, retention, and overwrite

Owner doc for how a plugin names, keys, retains, and overwrites durable artifacts it
writes under `${CLAUDE_PLUGIN_DATA}`. The migration playbook governs *what may live
there* (machine state only, never consumer configuration); this doc governs *how* those
artifacts are keyed so parallel projects, worktrees, and reruns do not collide or serve
stale findings from another checkout.

Upstream reference: [plugins reference — Persistent data
directory](https://code.claude.com/docs/en/plugins-reference), fetched 2026-08-12.
The directory resolves to `~/.claude/plugins/data/{id}/` with no project segment in the
formula. Reports and audit history are not among the documented intended uses
(dependencies, generated code, caches), so keying discipline is entirely
marketplace-owned.

## The hazard

`${CLAUDE_PLUGIN_DATA}` is **machine-global per plugin identifier**, not per project.
A fixed filename such as `last-audit.md` at the plugin root is silently overwritten by
the next run from any other repository on the machine. A skill that **reads back** that
file (`report` / `fix` modes) can present another project's findings as current — a wrong
answer, not merely a lost artifact.

A path that **looks** project-scoped but is not — kebab-cased basename of the project
root — still collides across forks, same-named worktrees, or two checkouts with the same
directory name. Timestamped filenames escape overwrite but not cross-match in duplicate
scans.

## Required key shape

Every durable report or run artifact under `${CLAUDE_PLUGIN_DATA}/<plugin-surface>/`
MUST include **project identity** in its path or filename unless the artifact is
explicitly machine-wide telemetry with no read-back contract.

**Canonical scheme** (reused across `claude-config` audit skills):

```
<state-key> = <repo-identity>/<worktree-discriminator>
```

- **`repo-identity`** — first configured remote URL normalized to `host/owner/repo`
  (lowercased, `.git` and credentials stripped). With no remote,
  `local/<sha256 of canonicalized repo root>` truncated to 12 hex chars.
- **`worktree-discriminator`** — `sha256` of the canonicalized worktree root,
  truncated to 8 hex chars. Two worktrees of one repository on different branches hold
  different content and must not share a report.

Write to:

```
${CLAUDE_PLUGIN_DATA}/<surface>/<state-key>/last-audit.md
```

or equivalent where `<surface>` names the skill or report family (`audit-instructions`,
`audit-prompting-postures`, `audit`, …).

### Read-back obligation

A skill that serves a stored report back to the operator (`report`, `fix`, `status`,
delta-vs-previous-run) MUST resolve the same `<state-key>` before read or write. Serving
a machine-global `last-audit.md` without project identity is a defect.

### History without overwrite

When reruns should not destroy prior output, prefer **one file per run** plus an
append-only history file (for example `state/history.jsonl` as the trend source of
truth), with a stable "read the latest" path keyed by `<state-key>`. Non-destructive
history alone does not close the read-back path — project identity is still required.

## Anti-pattern — looks scoped but is not

Keying only on the kebab-cased **basename** of `${CLAUDE_PROJECT_DIR}` (or git toplevel)
is insufficient: two repositories or worktrees sharing a basename resolve to one
directory. Document the hazard when illustrating this pattern; do not treat basename
slugging as project identity. Reference instance:
`bug-report` write skill Step 2 (context for the convention, not a defect filing).

## Retention and uninstall

The data directory is deleted when the plugin is uninstalled from the last scope where it
is installed (CLI default; `--keep-data` preserves). Design report trees accordingly:
avoid unbounded per-project forests that operators cannot reason about; prefer keyed
latest-plus-history over deep archival under `${CLAUDE_PLUGIN_DATA}`.

## Adopters

| Plugin / surface | Keying |
|---|---|
| `claude-config:audit-pass` | `<state-key>` under `runs/` and report paths — see run-state reference |
| `claude-config:audit-prompting-postures` | `<state-key>/last-audit.md` |
| `claude-config:unhobble` | `<experiment-id>` with manifest checkout identity verification |
| `machine-health:audit` | one file per run; `state/history.jsonl` trend |
| `claude-config:audit-instructions` | **pending** — fixed `last-audit.md` (#2276) |
| `claude-memory:audit` | **pending** — fixed `last-audit.md` (#2277) |
| `bug-report:write` | basename slug — documented anti-pattern example only |

## Conformance

Fleet audits check report-writing skills for `<state-key>` or equivalent project
identity before adopting new `${CLAUDE_PLUGIN_DATA}` writers. A new surface copies the
scheme from `audit-pass` rather than inventing a third doctrine.
