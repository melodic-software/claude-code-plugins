# Action: `recheck`

Update a recurring item's `last_checked` and `next_due` dates after completing a periodic check.

## Usage

```
recheck <text match or schedule ID>
```

Requires the consuming repo's `.github/recurring-schedule.json`. When the file is absent, report "no recurring schedule configured" and stop.

## Workflow

1. **Find the item in the recurring schedule:**

```bash
cat .github/recurring-schedule.json | jq --arg q "<query>" '
  .items[] | select(.id == $q or (.title | ascii_downcase | contains($q | ascii_downcase)))
'
```

If multiple matches, present them and ask the user to clarify.

1. **Update dates.** Always set `last_checked` to today. Only advance `next_due` if it's in the past or today — if it's already in the future, the consuming repo's recurring automation has already advanced it and re-advancing would skip a cycle.

| Cadence | Days |
|---------|------|
| `weekly` | 7 |
| `biweekly` | 14 |
| `monthly` | 30 |
| `quarterly` | 90 |
| `semi-annual` | 180 |
| `annual` | 365 |

1. **Edit `.github/recurring-schedule.json`:**

Read the current file, find the matched item, then:

- Set `last_checked` to today's date (always)
- If `next_due <= today`: set `next_due` to today + cadence days
- If `next_due > today`: leave `next_due` unchanged (already advanced by the recurring automation)

1. **Close the associated issue** (if one exists). Search for open issues with the `recurring` label matching the item's title (read — bare `gh`):

```bash
gh issue list --search "\"[Maintenance] <title>\" label:recurring" --state open --json number,title --limit 5 | tr -d '\r'
```

If found, close it with a recheck comment and clean up any claim label (writes):

```bash
gh issue close <N> --comment "Rechecked $(date +%Y-%m-%d). Next due: <next_due>." --reason completed
gh issue edit <N> --remove-label "status:claimed"
```

1. **Confirm:** "Rechecked: **{title}**. Next due: **{next_due}**"

## Notes

- Cadence is a minimum interval. On-demand rechecks are always valid
- If the consuming repo automates recurring-issue creation, a new issue will appear when `next_due` arrives
- If the schedule file was recently updated by automation, pull latest first
- The schedule file edit is a working-tree change — it gets committed and pushed with the PR for the work that triggered the recheck. If rechecking without other changes, commit from a feature branch and open a PR per the consuming repo's branching rules (never commit directly to a protected default branch)
