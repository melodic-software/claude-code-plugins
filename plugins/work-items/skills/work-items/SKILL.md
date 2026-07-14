---
name: work-items
description: "Manage development work items through the bound tracker (work-item-tracker seam). Actions: stats, list, add, work, start, done, due, recheck, search, scan, audit, decompose, triage. Use when: 'add a work item', 'add an issue', 'pick work', 'close a work item', 'list work items', 'what's due', 'work-item stats', 'search work items', 'scan TODOs', 'audit claims', 'break a plan into tickets', 'decompose into tickets', 'create issues from plan', 'triage', 'what needs triage', 'check overdue recurring items'. Covers codebase TODO/FIXME scanning, plan decomposition into vertical-slice tickets, stale-claim auditing, and recurring schedule checks. Not for new bug reports — use /bug-report:bug-report first (read-only report), then chain to /work-items:work-items add via --context if filing is needed."
argument-hint: "<action> [args] — actions: stats, list, add, work, start, done, due, recheck, search, scan, audit, decompose, triage (default: stats)"
user-invocable: true
disable-model-invocation: false
---

## Variables

Arguments: `$ARGUMENTS`

## Scope

This skill manages **development work items** — maintenance tasks, feature requests, bug reports, recurring audits, and housekeeping. It is the centralized, concurrent-safe work-item tracker.

**Provider-neutral over the seam.** Every tracker operation goes through the work-item-tracker seam — the skill calls `tools/work-item-tracker/work-item-tracker.sh <verb>` and the bound provider adapter executes it (contract: `tools/work-item-tracker/CONTRACT.md`). Resolve the seam path from the project root so invocations work from any subdirectory — `"${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/tools/work-item-tracker/work-item-tracker.sh" <verb>`; the executable snippets below use that rooted form. The repo's active provider is bound in `.work-item-tracker.json`. Coordination — create, claim (assignee + lease), lease renew/reclaim, dependency links, sub-items, frontier selection, single-item fetch — uses seam verbs directly. Operations without a core verb (listing with arbitrary filters, search, aggregation, close, label/comment edits) are provider-specific; for the bound GitHub adapter their mechanics live in `tools/work-item-tracker/adapters/github/README.md`. The skill core stays provider-portable and inlines no provider commands.

**Default = fix, not file.** Do NOT reflexively suggest `/work-items:work-items add` or `/work-items:work-items scan` for small / medium drift discovered while working. Boy Scout scope (cosmetic, stale counts, broken links, single-line corrections, one-paragraph clarifications) belongs in the current change, not the tracker. File NEW items only when the work is genuinely orthogonal to the current session, large enough to need its own `/architect` plan, or needs research the current session isn't positioned to do. Auto-suggesting `add` for fixable scope is the failure mode this rule prevents. When in doubt, fix in-place and surface what was fixed in the commit message / PR description.

**Label taxonomy.** Work items are classified along a prefix-axis grammar — UNIVERSAL axes (work in any repo) plus REPO-SPECIFIC axes carrying this repo's concrete values. Members are **not** snapshotted here: discover them live through the bound tracker adapter. When the consuming repository declares a label-as-code source of truth, that system owns writes and this skill remains read-only. The **type axis may be a native GitHub Issue Type** (`Bug`/`Feature`/`Task`) when the repository exposes it; otherwise use the repository's live `type:` labels. The grammar and citations live in [`reference/label-taxonomy.md`](reference/label-taxonomy.md).

| Axis | Mechanism | Scope | What it encodes |
|------|-----------|-------|-----------------|
| Type | native Issue Type (org) · `type:` label (personal) | universal | `Bug` / `Feature` / `Task` — the kind of issue; commit-type granularity stays at the commit layer |
| Priority | `priority:` | universal | urgency — members from the live set |
| Status | `status:` | universal | exception + gate flags only (`needs-info`, `needs-decision`, `ready`, `needs-triage`); claim = assignee + lease, blocked = native edge (neither is a label) |
| Meta | (none) | universal | `automated`, `recurring`, `agent-ready`, `needs-human`, `good-first-issue`, `migrated`, `stale` |
| Area | `area:` | repo-specific | the consuming repo's architecture surface — see `reference/label-taxonomy.md` |
| Category | `category:` | repo-specific | the consuming repo's domain categorization — see `reference/label-taxonomy.md` |
| Ecosystem | `ecosystem:` | repo-specific | the consuming repo's language/toolchain mix — see `reference/label-taxonomy.md` |
| Cadence | `cadence:` | repo-specific | e.g. `cadence:weekly`, `cadence:monthly` — members from the live set |

**Recurring schedule.** Recurring items are defined in `.github/recurring-schedule.json` and created as items by the consuming repo's recurring-issues automation when they come due. The `/work-items:work-items recheck` action updates this schedule after completing a periodic check.

## Emit checklist

For the `work` action (the most common multi-step path), instruct the agent to copy `templates/checklist.md` "Action: work" section into `.work/<slug>/work-items-checklist.md`. Tick each step as completed. For other actions (`add`, `start`, `done`, `recheck`), copy the matching action section. Single-action reads (`stats`, `list`, `search`, `scan`, `audit`) don't need a checklist.

## Action Router

Parse `$ARGUMENTS` to extract the action (first token) and remaining arguments.

| Action | Description | Detail |
|--------|-------------|--------|
| `stats` | Dashboard: open/claimed counts, overdue recurring, category breakdown | [actions/stats.md](actions/stats.md) |
| `list` | List work items with label/state/assignee filtering | [actions/list.md](actions/list.md) |
| `add` | Create a new work item with labels from the taxonomy | [actions/add.md](actions/add.md) |
| `work` | Auto-select one item and execute it via the project's development workflow | [actions/work.md](actions/work.md) |
| `start` | Claim an item (assignee + lease via the seam) | [actions/start.md](actions/start.md) |
| `done` | Close an item with a completion comment | [actions/done.md](actions/done.md) |
| `due` | Show recurring items past their `next_due` date | [actions/due.md](actions/due.md) |
| `recheck` | Update `last_checked`/`next_due` in recurring schedule after a periodic check | [actions/recheck.md](actions/recheck.md) |
| `search` | Full-text search across items (open + closed) | [actions/search.md](actions/search.md) |
| `scan` | Scan codebase for TODO/FIXME/HACK comments, create items from them | [actions/scan.md](actions/scan.md) |
| `audit` | Detect stale claims, orphaned recurring entries, label hygiene | [actions/audit.md](actions/audit.md) |
| `decompose` | Break a plan/PRD/item into vertical-slice work items with HITL/AFK classification and dependency ordering | [actions/decompose.md](actions/decompose.md) |
| `triage` | Evaluate incoming item: gather → recommend → reproduce → interview → apply outcome. No args = attention view | [actions/triage.md](actions/triage.md) |
| `help` | Show the action table above | *(inline)* |

If `$ARGUMENTS` is empty, run `stats`. If the action is unknown, show the action table.

---

## Operation routing

The skill core carries no provider commands. Every action routes its tracker operations one of two ways:

| Kind | Where |
|------|-------|
| **Coordination** — create, claim (assignee + lease), renew/reclaim lease, dependency links, sub-items, frontier selection, single-item fetch | Seam verbs: `tools/work-item-tracker/work-item-tracker.sh <verb>` — contract in `tools/work-item-tracker/CONTRACT.md` |
| **Provider mechanics** — list with filters, search, aggregate/count, close, label/assignee edits, comments | The bound adapter's operations reference (GitHub: `tools/work-item-tracker/adapters/github/README.md`) |

Coordination claims are race-safe at the seam (assignee + lease comment; `tools/work-item-tracker/CONTRACT.md` "Lease protocol") — the retired hold→verify→claim label dance is gone. Reads are non-mutating; writes route through the adapter's identity policy.

---

## Integration Points

### With `/workflow`

The project's development workflow — a `/workflow` skill, a CLAUDE.md workflow section, or team convention — applies to every item worked via `/work-items:work-items work`; the `work` action chains its full step sequence.

### With `/retro`

The retrospective skill's Phase 3 surfaces "Issue candidates" -- deferred research, discovered gaps, recurring recheck updates. Approved items use `/work-items:work-items add`. Mid-session learnings can be captured with `/retro codify`.

### With `/pull-request`

Branch name `<type>/<N>-<short-slug>` (proposed by `/work-items:work-items start` / `/work-items:work-items work`) carries the item number forward. `/pull-request create` parses the branch name and injects the closing keyword into the PR body; the pre-create gate verifies the keyword (or an opt-out marker) is present before creating the PR. Closing-keyword shape and PR body shape are owned by `/pull-request`.

`/work-items:work-items done --pr <N>` is the belt-and-suspenders path for manual PR flows where `/pull-request create` was not used: it verifies keyword presence on the unmerged PR body or falls back to closing the item when the PR has already merged (mechanics: the GitHub adapter README "PR closing-keyword mechanics").

### With autonomous agents

Items labeled `agent-ready` with no assignee are available for autonomous agent pickup. The `work` action's seam claim (assignee + lease) prevents concurrent agent collisions. The `audit` action detects stale claims from crashed/abandoned agent sessions.

### End-of-session check

At end of session, alongside `/retro`, check `/work-items:work-items due` to see if any recurring items need attention.

---

## Gotchas

Skill-behavior failure patterns. Add to this section when new gotchas are discovered. Provider-mechanic gotchas (Windows `\r`, search-qualifier syntax, the `gh` 30-row default limit, `--add-label` vs `--label`, `--reason` values, rate limits, Issue-Forms auto-labeling) live in the bound adapter's operations reference — for GitHub, `tools/work-item-tracker/adapters/github/README.md` "Gotchas".

- **Claim concurrency is the seam's job.** Claiming is race-safe at the seam (assignee + lease comment, same-identity aware) — `tools/work-item-tracker/CONTRACT.md` "Lease protocol". Reclaim runs idempotently at session start (`work` / `start`). Do not hand-roll a label-based hold protocol.
- **Recurring schedule is in `.github/`, not the skill directory.** The schedule file is `.github/recurring-schedule.json`. It's version-controlled and shared. The consuming repo's recurring-issues automation reads it; the `/work-items:work-items recheck` action updates it.

## What this skill does NOT do

- Inline provider (`gh`) commands — coordination goes through the seam, provider mechanics through the bound adapter reference.
- Own the label taxonomy content — that is `reference/label-taxonomy.md` (universal + repo-specific groups).
- Bind the provider — the active provider lives in `.work-item-tracker.json`, not here.
