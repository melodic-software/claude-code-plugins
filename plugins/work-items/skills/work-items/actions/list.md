# Action: `list`

List issues with optional filtering.

## Usage

```
list [--category <name>] [--label <name>] [--state <open|closed|all>] [--assignee <login>] [--limit <n>] [--search <query>]
```

## Flags

- `--category <name>` -- Filter by category label (adds `--label "category:<name>"`; values are the consuming repo's `category:` labels — see [`../reference/label-taxonomy.md`](../reference/label-taxonomy.md))
- `--label <name>` -- Filter by any label (repeatable, AND logic)
- `--state <s>` -- `open` (default), `closed`, `all`
- `--assignee <login>` -- Filter by assignee (`@me` for self)
- `--limit <n>` -- Max results (default: 30, max per request: 100)
- `--search <query>` -- Pass-through to `gh issue list --search` (GitHub search syntax)

## Workflow

1. Build the `gh issue list` command from parsed flags (read — bare `gh`):

```bash
gh issue list \
  --state open \
  --label "category:<name>" \
  --json number,title,state,labels,assignees,updatedAt \
  --limit 30 \
  | tr -d '\r'
```

1. Parse JSON and present as a condensed table:

```markdown
| # | Issue | Labels | Assignee | Updated |
|---|-------|--------|----------|---------|
| 1 | #42 Fix <thing> | type:fix, area:<name> | @user | 2d ago |
| 2 | #38 Review <config> | type:chore, category:<name> | -- | 5d ago |
```

The `#` column is a sequential index for this listing. When the user references an item by `#`, match it to the issue in the most recent listing.

## Search Syntax Reference

When using `--search`, the query uses GitHub's search syntax:

| Qualifier | Example | Meaning |
|-----------|---------|---------|
| `label:name` | `label:type:chore` | Has label |
| `-label:name` | `-label:stale` | Excludes label |
| `no:assignee` | `no:assignee` | Unassigned |
| `assignee:login` | `assignee:@me` | Assigned to user |
| `sort:field-dir` | `sort:created-asc` | Sort (created, updated, comments) |
| `created:>date` | `created:>2026-01-01` | Created after date |
| `updated:>date` | `updated:>2026-03-01` | Updated after date |
| text | `"fix authentication"` | Body/title text search |

Multiple qualifiers are AND-combined: `label:type:chore label:recurring no:assignee sort:created-asc`
