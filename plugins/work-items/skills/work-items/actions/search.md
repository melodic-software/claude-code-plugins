# Action: `search`

Full-text search across work items (open and closed).

## Usage

```
search "<query>"
```

## Workflow

1. **Search open issues** (read — bare `gh`; `--search` is the GitHub-search variant):

```bash
gh issue list --search "<query>" --state open --json number,title,state,labels,assignees --limit 20 | tr -d '\r'
```

1. **Search closed issues** (shows whether work was already done):

```bash
gh issue list --search "<query>" --state closed --json number,title,state,labels,closedAt --limit 10 | tr -d '\r'
```

1. **Search the recurring schedule** (skip when the consuming repo has no `.github/recurring-schedule.json`):

```bash
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
cat "$SCHEDULE" | jq --arg q "<query>" '
  [.items[] | select(
    (.id | ascii_downcase | contains($q | ascii_downcase)) or
    (.title | ascii_downcase | contains($q | ascii_downcase)) or
    (.notes // "" | ascii_downcase | contains($q | ascii_downcase)) or
    ([.triggers[]? // empty | ascii_downcase | contains($q | ascii_downcase)] | any)
  )]
'
```

1. **Present results grouped by source:**

```markdown
## Search: "{query}"

### Open Issues (X matches)

| # | Issue | Labels | Assignee |
|---|-------|--------|----------|
| 1 | #42 Fix analyzer false positive | type:fix | @user |

### Closed Issues (X matches)

| # | Issue | Closed |
|---|-------|--------|
| 1 | #15 Review linter config | 2026-03-23 |

### Recurring Schedule (X matches)

| # | Item | Cadence | Next Due |
|---|------|---------|----------|
| 1 | Review linter config | quarterly | 2026-06-21 |
```

If no matches anywhere: "No issues matching '{query}' in open, closed, or recurring."

## Search Syntax

The `--search` flag passes through to GitHub's search. Advanced syntax:

- `label:type:chore` -- filter by label
- `-label:stale` -- exclude label
- `no:assignee` -- unassigned only
- `sort:updated-desc` -- sort by last update
- `created:>2026-01-01` -- date filtering
- `"exact phrase"` -- exact match in title/body
