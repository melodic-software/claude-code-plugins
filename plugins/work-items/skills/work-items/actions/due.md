# Action: `due`

Show recurring items that are past their `next_due` date.

## Usage

```
/work-items:work-items due
```

## Workflow

1. **Read the recurring schedule:**

Read `.github/recurring-schedule.json` and filter items where `next_due <= today`. When the file is absent, report "no recurring schedule configured" and stop. Use jq for the initial filter:

```bash
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
if [[ -f "$SCHEDULE" ]]; then
  jq --arg today "$(date +%Y-%m-%d)" '
    [.items[] | select(.next_due != null and .next_due <= $today)]
    | sort_by(.next_due)
    | map({id, title, cadence, last_checked, next_due})
  ' "$SCHEDULE"
else
  echo "no recurring schedule configured"
fi
```

For days-overdue computation, calculate `(today - next_due)` in days. jq lacks date arithmetic, so compute this when presenting the table (parse the ISO dates and subtract).

1. **Cross-reference with open items.** For each due recurring item, check if one already exists (adapter: "List items", `--label recurring`, bare read). Match by title prefix `[Maintenance]` (the format used by the recurring-issues automation).

1. **Check for orphaned entries.** Entries in `recurring-schedule.json` with no corresponding item file or open item:

```bash
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
[[ -f "$SCHEDULE" ]] && jq -r '.items[].id' "$SCHEDULE"
```

1. **Present:**

```markdown
## Recurring Items Due

| # | Item | Cadence | Last Checked | Days Overdue | Open Item |
|---|------|---------|-------------|--------------|-----------|
| 1 | Review Directory.Packages.props | quarterly | 2026-03-23 | 15 | #52 |
| 2 | Review biome.json | quarterly | 2026-03-23 | 15 | -- |

**Orphaned entries** (in schedule but no matching item):
- {id}: {title} -- create item or remove entry
```

If nothing is due: "All recurring items are current. Next due: **{item}** on **{date}**."

## Notes

- Cadence is a minimum interval, not a lock. On-demand rechecks are always allowed via `/work-items:work-items recheck`.
- The `triggers` field in each schedule item lists external events that warrant early recheck regardless of cadence.
- When the user mentions a trigger event (e.g., ".NET 10.1 shipped"), proactively suggest relevant rechecks even if they aren't technically due yet.

## Documentation freshness (optional)

After presenting due items, when the user asks for a doc audit or maintenance is the focus, hand off to the consuming repo's documentation-audit tooling if it provides one (e.g. a doc-drift subagent or skill scoped to the repo's docs and rules) and surface the summary alongside the due table. Degrade gracefully — skip when no such tooling is present.
