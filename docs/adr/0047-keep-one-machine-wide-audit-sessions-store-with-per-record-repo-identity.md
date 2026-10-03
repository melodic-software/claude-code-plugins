# Keep one machine-wide audit-sessions store, with repo identity on each record

- Status: accepted
- Date: 2026-10-03

## Context

`audit-sessions` keeps a durable store of per-session numbers. Claude Code removes old transcripts
on its own schedule, so the store is the only lasting copy of those numbers. The skill's main mode
sweeps every session on the machine, and `--scope project` narrows the sweep to one repository.

The plan first keyed the store per checkout with the vendored `lib/state-key.sh` rule, as
session-flow keys its other per-project state. One person works across many checkouts and worktrees
of the same repositories, and worktrees are pruned after merge. A worktree's transcripts can also
outlive its directory: 20 of 103 records in the first real-corpus probe had no resolvable identity
because their working directory had been removed.

## Decision

1. **One store per machine**, under `${CLAUDE_PLUGIN_DATA}/audit-sessions/store/`, versioned by
   schema. The machine-wide sweep reads it directly.
2. **Each session record carries its own repository identity**, resolved at collect time from the
   session's working directory. It is null when that directory no longer exists. The record does
   not store the raw working directory; its path in the store is keyed by a hash of the project
   directory name.
3. **Only reports are keyed per repository or ticket.** `--scope project` takes the state key
   `lib/state-key.sh` prints (`<identity>/<worktree>`), keeps the records whose repository identity
   matches its identity part, so every checkout and worktree of the repository counts, and writes
   its report under the full key.
4. **Nothing in the store is committed**, and uninstalling the plugin deletes it. The skill says so
   before the first collect on a machine.

## Alternatives considered

- **A store per checkout, keyed by state key.** Rejected: it splits the all-projects sweep across
  many stores, strands records under the keys of pruned worktrees, and makes the machine-wide view
  the expensive case.
- **A store inside each repository's memory tier.** Rejected: it is checkout-local, so it dies with
  the worktree, and the machine-wide sweep would have to discover every checkout.

## Consequences

- The machine-wide sweep reads one directory. A project sweep filters records rather than opening a
  separate store.
- Sessions whose working directory was removed before collect stay in machine-wide numbers but drop
  out of every project-scoped report.
- Retention is one machine-wide setting (`audit_sessions_retention_days`), not one per repository.
- Other session-flow state keeps its per-project keying. This decision covers the `audit-sessions`
  store only.
