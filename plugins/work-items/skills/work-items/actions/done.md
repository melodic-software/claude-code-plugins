# Action: `done`

Close an issue with a completion comment.

## Usage

```
done <number or text match> [--summary "completion summary"] [--pr <number>] [--not-planned]
```

## Flags

- `--summary "text"` -- Completion summary (required -- will prompt if missing)
- `--pr <number>` -- Link the closing PR
- `--not-planned` -- Close as "not planned" instead of "completed" (for issues decided against or superseded)

## Workflow

1. **Resolve the issue.** If a number is given, use it directly. If text, search open issues.

1. **Check if recurring** (skip when the consuming repo has no `.github/recurring-schedule.json`). Issues created by recurring automation have a `[Maintenance]` prefix, so strip it before comparing:

```bash
cat .github/recurring-schedule.json | jq --arg title "<issue title>" '
  ($title | ltrimstr("[Maintenance] ")) as $stripped |
  [.items[] | select(.title == $stripped or .title == $title or .id == "<kebab-id>")] | length
'
```

If it's a recurring item, warn: "This is a recurring item. Did you mean the `recheck` action instead?" Proceed only if the user confirms.

1. **Build the closing comment:**

```markdown
**Done (YYYY-MM-DD):** {summary}

{if --pr: Fixed in #{pr_number}}
```

1. **Close the issue** (write). Use `--reason "not planned"` when `--not-planned` was passed:

```bash
gh issue close <N> --comment "Done ($(date +%Y-%m-%d)): {summary}" --reason completed
# with --not-planned:
gh issue close <N> --comment "Closing ($(date +%Y-%m-%d)): {summary}" --reason "not planned"
```

1. **Clean up claim labels** (write):

```bash
gh issue edit <N> --remove-label "status:claimed"
```

1. **Belt-and-suspenders: verify PR body keyword presence.** This step fires when `done` is invoked for a manual PR flow (no PR tooling injected a closing keyword). Only runs when `--pr` is provided:

```bash
PR_BODY=$(mktemp)
gh pr view <PR> --json body,mergedAt --jq '.body' | tr -d '\r' > "$PR_BODY"
KEYWORD_REGEX='^(close|closes|closed|fix|fixes|fixed|resolve|resolves|resolved):? #[0-9]+'
OPTOUT_REGEX='^(Refs #[0-9]+|No related issue:)'

if grep -iE "$KEYWORD_REGEX" "$PR_BODY" >/dev/null; then
  :  # keyword present — auto-close will fire on merge
elif grep -E "$OPTOUT_REGEX" "$PR_BODY" >/dev/null; then
  :  # explicit opt-out — leave PR body alone
else
  # PR body lacks keyword AND lacks opt-out. Behavior depends on merge state.
  MERGED_AT=$(gh pr view <PR> --json mergedAt --jq '.mergedAt')
  if [[ -z "$MERGED_AT" || "$MERGED_AT" == "null" ]]; then
    # Unmerged — read-modify-write the PR body to prepend `Closes #<N>`
    # (`--body-file` REPLACES, never appends). Write op.
    printf '%s\n\n%s\n' "Closes #<N>" "$(cat "$PR_BODY")" | gh pr edit <PR> --body-file -
  fi
  # Merged — keyword can no longer auto-fire. Step 4's `gh issue close <N>`
  # is the only remaining path.
fi
rm -f "$PR_BODY"
```

If keyword present → GitHub auto-closes the issue on merge (the structural path). If absent on an unmerged PR → read-modify-write injects `Closes #<N>` at top of body. If absent on a merged PR → step 4's manual `gh issue close` is the only remaining path; keyword can no longer auto-fire.

1. **Confirm:** "Closed **#N**: {title}. Summary: {summary}"

## Notes

- Always require a completion summary. Summaries are institutional memory of what was decided/learned
- If no `--summary` provided, ask for one before closing
- The `--reason` flag accepts `completed` (default) or `not planned`. Use `not planned` for issues that were decided against, superseded, or no longer relevant
