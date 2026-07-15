# Action: `recheck`

Update a recurring item's `last_checked` and `next_due` dates after completing a periodic check.

## Usage

```
/work-items:work-items recheck <text match or schedule ID>
```

## Workflow

1. **Resolve the recurring-maintenance role label before any tracker read.** Read
   `.work-item-tracker.json` at action entry and resolve
   `config.role_labels["recurring-maintenance"]`; use `recurring` only when the file or entry is
   absent. Stop on a malformed, empty, or non-string configured value. Use the resolved string in
   the search below.

1. **Find the item in the recurring schedule:**

```bash
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
if [[ -f "$SCHEDULE" ]]; then
  jq --arg q "<query>" '
    .items[] | select(.id == $q or (.title | ascii_downcase | contains($q | ascii_downcase)))
  ' "$SCHEDULE"
fi
```

If multiple matches, present them and ask the user to clarify.

1. **Update dates.** Always set `last_checked` to today. Only advance `next_due` if it's in the past or today — if it's already in the future, the recurring-issues automation has already advanced it and re-advancing would skip a cycle.

| Cadence | Days |
|---------|------|
| `weekly` | 7 |
| `biweekly` | 14 |
| `monthly` | 30 |
| `quarterly` | 90 |
| `semi-annual` | 180 |
| `annual` | 365 |

1. **Edit `.github/recurring-schedule.json`:**

Re-read the current file from disk immediately before writing (the schedule is shared; never write back a stale in-context copy), find the matched item, then — touching only that row, preserving all others:

- Set `last_checked` to today's date (always)
- If `next_due <= today`: set `next_due` to today + cadence days
- If `next_due > today`: leave `next_due` unchanged (already advanced by the recurring workflow)

1. **Close the associated item** (if one exists). Search for open items with the resolved
   recurring-maintenance label (adapter: "Search items",
   `label:<resolved recurring-maintenance label>` + the `[Maintenance]` title, bare read). Provider
   search is substring/prefix, not exact-title equality, so **filter the results to the item whose
   title equals `[Maintenance] {title}` exactly** before closing — otherwise a shorter title
   (`Review CI`) could close a longer item's issue (`[Maintenance] Review CI workflow pins`). Close
   only the exact match, with a recheck comment (adapter: "Close item"), reason `completed`, comment
   "Rechecked YYYY-MM-DD. Next due: <next_due>.".

1. **Confirm:** "Rechecked: **{title}**. Next due: **{next_due}**"

## Notes

- Cadence is a minimum interval. On-demand rechecks are always valid.
- The recurring-issues automation will create a new item when `next_due` arrives.
- If the schedule file was recently updated by the workflow's PR, pull latest first.
- The schedule file edit is a working-tree change — it gets committed and pushed with the PR for the work that triggered the recheck. If rechecking without other changes, commit from your feature branch and open a PR: `git add .github/recurring-schedule.json && git commit -m "chore: advance recurring schedule for <item>"` (never commit directly to main).
