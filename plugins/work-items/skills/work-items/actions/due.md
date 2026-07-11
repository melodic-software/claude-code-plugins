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
# Root the path at the project root — a relative path breaks when invoked from a subdirectory.
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
cat "$SCHEDULE" | jq --arg today "$(date +%Y-%m-%d)" '
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

Match each schedule row against the FULL expected title `[Maintenance] {schedule item title}` — never by the bare `[Maintenance]` prefix alone, or any recurring issue would satisfy every due row.

1. **Check for orphaned entries.** Only DUE entries (`next_due <= today`) without a corresponding open issue are orphan-suspect — future items legitimately have no issue yet (recurring automation creates issues only when an item becomes due):

```bash
# Due item IDs only — future rows are healthy without an issue
cat "$SCHEDULE" | jq -r --arg today "$(date +%Y-%m-%d)" '.items[] | select(.next_due != null and .next_due <= $today) | .id'
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
