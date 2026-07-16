# Action: `done`

Close a work item with a completion comment.

## Usage

```
/work-items:track done <number or text match> [--summary "completion summary"] [--pr <number>] [--not-planned]
```

## Flags

- `--summary "text"` -- Completion summary (required -- will prompt if missing)
- `--pr <number>` -- Link the closing PR
- `--not-planned` -- Close as "not planned" instead of "completed" (for items decided against or superseded)

## Workflow

1. **Resolve the item.** If a number is given, use it directly. If text, search open items (adapter: "Search items").

1. **Check if recurring.** Read `.github/recurring-schedule.json` and check if the item's title matches any recurring item. Items created by the recurring-issues automation have a `[Maintenance]` prefix, so strip it before comparing. Skip gracefully when the repo has no recurring schedule:

```bash
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
if [[ -f "$SCHEDULE" ]]; then
  jq --arg title "<item title>" '
    ($title | ltrimstr("[Maintenance] ")) as $stripped |
    [.items[] | select(.title == $stripped or .title == $title or .id == "<kebab-id>")] | length
  ' "$SCHEDULE"
else
  echo 0  # no recurring schedule configured
fi
```

If it's a recurring item, warn: "This is a recurring item. Did you mean `/work-items:track recheck` instead?" Proceed only if the user confirms.

1. **Build the closing comment:**

```markdown
**Done (YYYY-MM-DD):** {summary}

{if --pr: Fixed in #{pr_number}}
```

1. **Close the item — unless an unmerged `--pr` will auto-close THIS item.** When `--pr` names an UNMERGED PR, run the keyword step below first and branch on what it leaves on the PR body:
   - **`Closes #<N>` for THIS item is present (or the keyword step just added it)** → do NOT close manually: post the completion summary as a plain comment (adapter: "Comment on item") and report "will auto-close when #{pr} merges".
   - **The PR body carries a deliberate opt-out for THIS item (`Refs #<N>` / `No related issue:`), so a merge will NOT close it** → do NOT claim auto-close. Post the completion comment and leave the item open, reporting that #{pr} will not close it (the opt-out was intentional — ask the user if they actually want it closed). A closing keyword for a *different* issue never counts as this item's auto-close.

   Closing now would mark the item done before the work has landed — a failed or abandoned PR would leave it wrongly closed. Close directly (adapter: "Close item" — WRITE via the adapter's identity policy), passing the closing comment and `--reason completed` (or `not planned` for `--not-planned`), ONLY when there is no `--pr` or the named PR has already merged.

   The seam claim is a lease (assignee + lease comment), not a label — closing removes the item from the frontier, so no `status:*` label cleanup is part of this flow (the retired `status:claimed` label is handled by the label-reconciliation migration, not here).

1. **Belt-and-suspenders: verify PR body keyword presence.** Primary path is the `/pull-request create` §2.4.2 pre-create gate (covers all 9 closing keywords + opt-out markers). This step fires when `/work-items:track done` is invoked WITHOUT having gone through `/pull-request create` (rare — manual close path). Only runs when `--pr` is provided.

   Apply the read-modify-write keyword check + prepend from the adapter "PR closing-keyword mechanics" section, keyed to THIS item's `#<N>`: if the (unmerged) PR body carries neither a closing keyword for `#<N>` (`Closes #<N>`) nor an opt-out marker for it (`Refs #<N>` / `No related issue:`), prepend `Closes #<N>` — a closing keyword targeting a *different* issue does not count. If an opt-out marker for `#<N>` is present, leave the body alone (Step 4's opt-out branch handles it); if merged, the keyword can no longer auto-fire and Step 4's close is the only path.

1. **Confirm:** "Closed **#N**: {title}. Summary: {summary}"

## Notes

- Always require a completion summary. Summaries are institutional memory of what was decided/learned.
- If no `--summary` provided, ask for one before closing.
- The `done` action closes with `completed` (default), or `not planned` when `--not-planned` is given — for items decided against, superseded, or no longer relevant.
