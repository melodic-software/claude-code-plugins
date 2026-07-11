# Action: `due`

Show recurring items that are past their `next_due` date.

## Usage

```
due
```

Requires the consuming repo's `.github/recurring-schedule.json`. When the file is absent, report "no recurring schedule configured" and stop — see the SKILL body "Recurring schedule (optional consumer infrastructure)".

## Workflow

1. **Read the recurring schedule:**

Read `.github/recurring-schedule.json` and filter items where `next_due <= today`. Use jq for the initial filter:

```bash
cat .github/recurring-schedule.json | jq --arg today "$(date +%Y-%m-%d)" '
  [.items[] | select(.next_due != null and .next_due <= $today)]
  | sort_by(.next_due)
  | map({id, title, cadence, last_checked, next_due})
'
```

For days-overdue computation, calculate `(today - next_due)` in days. jq lacks date arithmetic, so compute this when presenting the table (e.g., parse the ISO dates and subtract).

1. **Cross-reference with open issues.** For each due recurring item, check if an issue already exists (read — bare `gh`):

```bash
gh issue list --label "recurring" --state open --json number,title --limit 50 | tr -d '\r'
```

Match by title prefix `[Maintenance]` (the convention used by recurring automation and `add --recurring`).

1. **Check for orphaned entries.** Entries in `recurring-schedule.json` that don't have a corresponding open issue:

```bash
# List all recurring item IDs from schedule
cat .github/recurring-schedule.json | jq -r '.items[].id'
```

1. **Present:**

```markdown
## Recurring Items Due

| # | Item | Cadence | Last Checked | Days Overdue | Open Issue |
|---|------|---------|-------------|--------------|------------|
| 1 | Review dependency manifest | quarterly | 2026-03-23 | 15 | #52 |
| 2 | Review linter config | quarterly | 2026-03-23 | 15 | -- |

**Orphaned entries** (in schedule but no matching issue):
- {id}: {title} -- create issue or remove entry
```

If nothing is due: "All recurring items are current. Next due: **{item}** on **{date}**."

## Notes

- Cadence is a minimum interval, not a lock. On-demand rechecks are always allowed via the `recheck` action
- The `triggers` field in each schedule item lists external events that warrant early recheck regardless of cadence
- When the user mentions a trigger event (e.g., a new framework release shipped), proactively suggest relevant rechecks even if they aren't technically due yet
