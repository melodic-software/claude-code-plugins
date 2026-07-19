# Action: `stats`

Present a dashboard summarizing the current state of work items.

## Workflow

1. **Fetch category counts** and **status/assignee counts** using the aggregation projections in the bound adapter's operations reference (GitHub: `${CLAUDE_PLUGIN_ROOT}/tools/work-item-tracker/adapters/github/README.md` "Aggregate / count (dashboard + hygiene)" — bare reads).

1. **Check recurring due items** (optional — degrade gracefully when the consuming repo has no recurring schedule):

```bash
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
if [[ -f "$SCHEDULE" ]]; then
  jq --arg today "$(date +%Y-%m-%d)" \
    '[.items[] | select(.next_due != null and .next_due <= $today)] | length' "$SCHEDULE"
else
  echo 0  # no recurring schedule configured
fi
```

1. **Present:**

```markdown
## Work Items Dashboard

| Category | Open |
|----------|------|
| category:<your-category-1> | X |
| category:<your-category-2> | X |
| (one row per `category:` label the repo defines) | |
| **Total** | **X** |

**Claimed:** X items (assigned — a seam claim is an assignee + lease)
**Unassigned:** X items (no assignee, available for pickup)
**Recurring due:** X items past their `next_due` date (use `/work-items:track due` to see them)
```

## Notes

- If the repo has >100 open items, the `--limit 500` aggregation cap means counts are approximate. Add a note: "Showing top 100. Use `/work-items:track list` with filters for the full set."
- For the category breakdown, items with no `category:*` label are counted as "uncategorized."
