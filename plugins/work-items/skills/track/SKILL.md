---
name: track
description: "Track development work items through the bound tracker (work-item-tracker seam) — the backlog-CRUD multi-verb skill. Actions: stats, list, add, start, done, due, recheck, search, audit (default: stats dashboard). Use when: 'add a work item', 'add an issue', 'close a work item', 'start a work item', 'claim a work item', 'list work items', 'what work items are open', 'what's due', 'work-item stats', 'work items dashboard', 'search work items', 'check overdue recurring items', 'recheck a recurring item', 'audit work items', 'audit stale claims'. Not for new bug reports — use /bug-report:write first (read-only report), then chain to /work-items:track add via --context if filing is needed. Sibling skills own the other verbs: /work-items:work (auto-select + execute one), /work-items:triage (raw intake), /work-items:decompose (plan → tickets), /work-items:scan-todos (TODO/FIXME sweep)."
argument-hint: "<action> [args] — actions: stats, list, add, start, done, due, recheck, search, audit (default: stats)"
user-invocable: true
disable-model-invocation: false
---

## Variables

Arguments: `$ARGUMENTS`

## Shared tracker context

The seam, operation routing, label taxonomy, canonical-role remapping, recurring schedule, and
topic-docs binding that every work-items skill relies on live in
[`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
(and the references it links). Read it at the start of an invocation. Two invariants bear on the
actions below in particular:

- **Provider-neutral over the seam.** Coordination goes through
  `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh <verb>`; provider mechanics (filtered listing,
  search, aggregation, close, label/comment edits) route through the bound adapter's operations
  reference. The core inlines no provider commands.
- **Role-label resolution is an action-entry invariant.** `add`, `due`, `recheck`, and `audit`
  query, create, or filter items by a canonical role — resolve each role from
  `.work-item-tracker.json` `config.role_labels` at action entry and use the resolved strings in
  every query. When a role defaults because the file or entry is absent, warn loudly rather than
  substituting silently; a present malformed/empty/non-string value is a hard stop.

## Scope

`track` is the centralized, concurrent-safe backlog-CRUD surface: create, claim, close, list,
search, dashboard, and the recurring-schedule checks. It keeps a sub-action router over nine verbs.
Auto-selecting and executing one item is the sibling `/work-items:work` skill; raw-intake
evaluation is `/work-items:triage`; plan decomposition is `/work-items:decompose`; the codebase
marker sweep is `/work-items:scan-todos`.

## Emit checklist

For the multi-step actions (`add`, `start`, `done`, `recheck`), instruct the agent to copy the
matching action section of
[`${CLAUDE_PLUGIN_ROOT}/templates/checklist.md`](${CLAUDE_PLUGIN_ROOT}/templates/checklist.md) into
`<memory_dir>/<slug>/work-items-checklist.md` (default `.work/`) — a memory-tier write under this
plugin's topic-docs binding
([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)):
derive `<slug>` per its slug spec and, on the session's first memory-tier write, verify the resolved
memory root's self-ignore guard (a `.gitignore` containing `*`, created and announced when absent).
Tick each step as completed. Single-action reads (`stats`, `list`, `search`, `audit`, `due`) don't
need a checklist.

## Action Router

Parse `$ARGUMENTS` to extract the action (first token) and remaining arguments.

| Action | Description | Detail |
|--------|-------------|--------|
| `stats` | Dashboard: open/claimed counts, overdue recurring, category breakdown | [actions/stats.md](actions/stats.md) |
| `list` | List work items with label/state/assignee filtering | [actions/list.md](actions/list.md) |
| `add` | Create a new work item with labels from the taxonomy | [actions/add.md](actions/add.md) |
| `start` | Claim an item (assignee + lease via the seam) | [actions/start.md](actions/start.md) |
| `done` | Close an item with a completion comment | [actions/done.md](actions/done.md) |
| `due` | Show recurring items past their `next_due` date | [actions/due.md](actions/due.md) |
| `recheck` | Update `last_checked`/`next_due` in recurring schedule after a periodic check | [actions/recheck.md](actions/recheck.md) |
| `search` | Full-text search across items (open + closed) | [actions/search.md](actions/search.md) |
| `audit` | Detect stale claims, orphaned recurring entries, label hygiene | [actions/audit.md](actions/audit.md) |
| `help` | Show the action table above | *(inline)* |

If `$ARGUMENTS` is empty, run `stats` (the default dashboard). If the action is unknown, show the
action table.

**Verbs that moved to sibling skills.** `work`, `triage`, `decompose`, and `scan` are no longer
`track` sub-actions — they are standalone skills. If `$ARGUMENTS` names one of them, point the user
at the skill instead of erroring: `work` → `/work-items:work`, `triage` → `/work-items:triage`,
`decompose` → `/work-items:decompose`, `scan` → `/work-items:scan-todos`.
