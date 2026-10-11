---
description: "Backlog CRUD through the bound tracker: stats, list, add, start, done, due, recheck, search, audit, link (default: stats). Use when the user wants to add, claim, or close a work item, ticket, or issue; list, search, or see a dashboard of open items; check what is due on the recurring schedule; or audit stale claims and labels. New bug reports go to /bugs:write first. Picking and executing the next item is /work-items:work; raw intake is /work-items:triage."
argument-hint: "[stats|list|add|start|done|due|recheck|search|audit|link|help] [args]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Backlog CRUD through the bound tracker. Add, list, close, stats
---

## Variables

Arguments: `$ARGUMENTS`. `[stats|list|add|start|done|due|recheck|search|audit|link|help] [args]`. The default action is stats. The actions are stats, list, add, start, done, due, recheck, search, audit, link, and help.

## Shared tracker context

The seam, operation routing, label taxonomy, canonical-role remapping, recurring schedule, and
memory-tier write rule that every work-items skill relies on live in
[`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
(and the references it links). Read it at the start of an invocation. Two invariants bear on the
actions below in particular:

- **Provider-neutral over the seam.** Coordination goes through
  `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/work-item-tracker.sh <verb>`; provider mechanics (filtered listing,
  search, aggregation, close, label/comment edits) route through the bound adapter's operations
  reference. The core inlines no provider commands.
- **Role-label resolution is an action-entry invariant.** `add`, `due`, `recheck`, and `audit`
  query, create, or filter items by a canonical role. Resolve each role from
  `.work-item-tracker.json` `config.role_labels` at action entry and use the resolved strings in
  every query. An absent file or entry falls back to the documented default without a warning (a
  conforming binding omits entries that keep their default); a present malformed, empty, or
  non-string value is a hard stop.

`add` and `recheck` also draw on reference files the seam doc above does not itself carry:

- [`${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md`](${CLAUDE_PLUGIN_ROOT}/reference/label-taxonomy.md):
  the label structure `add` validates against and `list --category` filters by.
- [`${CLAUDE_PLUGIN_ROOT}/reference/issue-conventions.md`](${CLAUDE_PLUGIN_ROOT}/reference/issue-conventions.md):
  the title convention `add` applies.
- [`${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/agent-brief.md):
  the brief template `add --agent-ready` uses instead of the default body.
- [`${CLAUDE_PLUGIN_ROOT}/reference/standing-item-preconditions.md`](${CLAUDE_PLUGIN_ROOT}/reference/standing-item-preconditions.md):
  the precondition `recheck` evaluates before advancing dates or closing the associated item.

## Scope

`track` is the centralized, concurrent-safe backlog-CRUD surface: create, claim, close, list,
search, dashboard, and the recurring-schedule checks. It keeps a sub-action router over the verbs
in the table below.
Auto-selecting and executing one item is the sibling `/work-items:work` skill; raw-intake
evaluation is `/work-items:triage`; plan decomposition is `/work-items:decompose`; the codebase
marker sweep is `/work-items:scan-todos`.

## Emit checklist

For the multi-step actions (`add`, `start`, `done`, `recheck`), instruct the agent to copy the
matching action section of
[`${CLAUDE_PLUGIN_ROOT}/templates/checklist.md`](${CLAUDE_PLUGIN_ROOT}/templates/checklist.md) into
`<memory_dir>/<slug>/work-items-checklist.md` (default `.work/`), a memory-tier write
([`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
"Memory-tier writes" owns the slug and the self-ignore guard).
Tick each step as completed. Single-action reads (`stats`, `list`, `search`, `audit`, `due`) don't
need a checklist.

## Next

- A picked item: `/work-items:work`.
- Raw intake: `/work-items:triage`.

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
| `link` | The adapter's text linking a change to an item, from an id or a branch name | [actions/link.md](actions/link.md) |
| `help` | Show the action table above | *(inline)* |

If `$ARGUMENTS` is empty, run `stats` (the default dashboard). If the action is unknown, show the
action table.

**Sibling-skill verbs.** `work`, `triage`, `decompose`, and `scan` are standalone skills, not
`track` sub-actions. If `$ARGUMENTS` names one of them, point the user
at the skill instead of erroring: `work` → `/work-items:work`, `triage` → `/work-items:triage`,
`decompose` → `/work-items:decompose`, `scan` → `/work-items:scan-todos`.
