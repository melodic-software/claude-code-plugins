# Action: `search`

Full-text search across work items (open and closed).

## Usage

```
/work-items:track search "<query>"
```

## Workflow

1. **Search open + closed items** using the adapter's search path (adapter: "Search items" — bare reads; run once for `--state open` and once for `--state closed` to show whether work was already done).

1. **Search recurring schedule** (skip gracefully when the repo has no recurring schedule):

```bash
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
[[ -f "$SCHEDULE" ]] && jq --arg q "<query>" '
  [.items[] | select(
    (.id | ascii_downcase | contains($q | ascii_downcase)) or
    (.title | ascii_downcase | contains($q | ascii_downcase)) or
    (.notes // "" | ascii_downcase | contains($q | ascii_downcase)) or
    ([.triggers[]? // empty | ascii_downcase | contains($q | ascii_downcase)] | any)
  )]
' "$SCHEDULE"
```

1. **Present results grouped by source:**

```markdown
## Search: "{query}"

### Open Items (X matches)

| # | Item | Type | Labels | Assignee |
|---|------|------|--------|----------|
| 1 | #42 Fix analyzer false positive | Bug | area: analyzers | @agent1 |

### Closed Items (X matches)

| # | Item | Closed |
|---|------|--------|
| 1 | #15 Review .editorconfig | 2026-03-23 |

### Recurring Schedule (X matches)

| # | Item | Cadence | Next Due |
|---|------|---------|----------|
| 1 | Review biome.json | quarterly | 2026-06-21 |
```

If no matches anywhere: "No items matching '{query}' in open, closed, or recurring."

## Search syntax

The provider's search qualifiers (label / exclude / assignee / sort / date / exact-phrase) are documented in the bound adapter's operations reference — GitHub: `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/adapters/github/README.md` "Search items".
