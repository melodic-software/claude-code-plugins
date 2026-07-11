# Action: `stats`

Present a dashboard summarizing the current state of the work-item tracker.

## Workflow

1. **Fetch category counts** (read — bare `gh`):

```bash
gh issue list --state open --json labels --limit 500 --jq '
  [.[].labels[].name] | map(select(startswith("category:"))) | group_by(.) | map({key: .[0], count: length}) | sort_by(.key)
' | tr -d '\r'
```

1. **Fetch status counts:**

```bash
gh issue list --state open --json labels,assignees --limit 500 --jq '
  { total: length,
    considering: [.[] | select(any(.labels[]; .name == "status:considering"))] | length,
    claimed: [.[] | select(any(.labels[]; .name == "status:claimed"))] | length,
    unassigned: [.[] | select(.assignees | length == 0)] | length }
' | tr -d '\r'
```

1. **Check recurring due items** by reading `.github/recurring-schedule.json` (skip this step with a "no recurring schedule configured" note when the file is absent):

```bash
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
cat "$SCHEDULE" | jq --arg today "$(date +%Y-%m-%d)" '
  [.items[] | select(.next_due != null and .next_due <= $today)] | length
'
```

1. **Present:**

```markdown
## Work-Item Dashboard

| Category | Open |
|----------|------|
| category:<name> | X |
| (one row per category label in the repo) | |
| **Total** | **X** |

**Considering:** X issues (held by an agent via `status:considering`)
**Claimed:** X issues (assigned + `status:claimed`)
**Unassigned:** X issues (no assignee, available for pickup)
**Recurring due:** X items past their `next_due` date (use the `due` action to see them)
```

## Notes

- If the repo has >100 open issues, the `--limit 500` cap means counts are approximate. Add a note: "Counts approximate. Use the `list` action with filters for the full set."
- For the category breakdown, issues with no `category:*` label are counted as "uncategorized."
