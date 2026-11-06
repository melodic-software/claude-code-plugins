# Action: `recheck`

Update a recurring item's `last_checked` and `next_due` dates after completing a periodic check.

## Usage

```
/work-items:track recheck <text match or schedule ID>
```

## Workflow

1. **Resolve the recurring-maintenance role label before any tracker read.** Read
   the binding the seam resolves (the `tracker` mapping of `<home>/work-items.yaml`, else the
   legacy repo-root JSON binding) at action entry and resolve
   `config.role_labels["recurring-maintenance"]`; use `recurring` when the file or entry is
   absent (the documented default, no warning). Stop on a malformed, empty, or non-string
   configured value. Use the resolved string in the item read below.

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

1. **Evaluate any `precondition` on the matched row** before mutating dates or closing the issue ([`${CLAUDE_PLUGIN_ROOT}/reference/standing-item-preconditions.md`](${CLAUDE_PLUGIN_ROOT}/reference/standing-item-preconditions.md)):

```bash
EVAL="${CLAUDE_PLUGIN_ROOT}/scripts/evaluate-schedule-precondition.sh"
[[ -f "$EVAL" ]] || EVAL="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/plugins/work-items/scripts/evaluate-schedule-precondition.sh"
"$EVAL" "$SCHEDULE" "<matched-id>"   # add --operator-confirmed when the operator affirmed
```

Refuse to advance `last_checked`/`next_due` or close the associated issue when the helper exits `2` (`needs-confirmation`) or `1` (`unmet`). Surface the printed prompt inline instead.

1. **Update dates.** Always set `last_checked` to today. Only advance `next_due` if it's in the past or today. If it's already in the future, an earlier recheck this cycle already advanced it (the recurring-issues automation only files items and never edits the schedule), and re-advancing would skip a cycle.

Cadence-to-days values: the Cadence Duration Table in [`add.md`](add.md#cadence-duration-table).

1. **Edit `.github/recurring-schedule.json`:**

Re-read the current file from disk immediately before writing (the schedule is shared; never write back a stale in-context copy), find the matched item, then edit only that row, preserving all others:

- Set `last_checked` to today's date (always)
- If `next_due <= today`: set `next_due` to today + cadence days
- If `next_due > today`: leave `next_due` unchanged (already advanced this cycle)

1. **Close the associated item** (if one exists). Search for open items with the resolved
   recurring-maintenance label (adapter: "List items", `--label <resolved recurring-maintenance
   label>`, with bodies, bare read), and **keep only the item whose body has the matched row's
   `<!-- recurring-schedule id=<id> -->` line**, the `id` equal exactly
   ([`reference/issue-conventions.md`](../../../reference/issue-conventions.md)
   "Recurring marker"). Never match by title: a title search would let a row titled `Review CI`
   close the item for `Review CI workflow pins`. Close only that item, with a recheck comment
   (adapter: "Close item"), reason `completed`, comment "Rechecked YYYY-MM-DD. Next due:
   <next_due>.".

1. **Confirm:** "Rechecked: **{title}**. Next due: **{next_due}**"

## Notes

- Cadence is a minimum interval. On-demand rechecks are always valid.
- The recurring-issues automation will create a new item when `next_due` arrives.
- If another PR recently updated the schedule file, pull latest first.
- The schedule file edit is a working-tree change. It gets committed and pushed with the PR for the work that triggered the recheck. If rechecking without other changes, commit from your feature branch and open a PR: `git add .github/recurring-schedule.json && git commit -m "chore: advance recurring schedule for <item>"` (never commit directly to main).
