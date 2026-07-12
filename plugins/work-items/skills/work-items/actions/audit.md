# Action: `audit`

Detect stale claims, orphaned recurring entries, and label hygiene issues.

## Usage

```
audit
```

## Checks

### 1. Stale Holds

Issues with `status:considering` label that haven't been promoted to `status:claimed` within 15 minutes (abandoned evaluation or agent crash). Reads use bare `gh`:

```bash
gh issue list --label "status:considering" --state open --json number,title,updatedAt --limit 50 | tr -d '\r'
```

For each issue, list the hold comments and read each hold's age from its embedded epoch timestamp (`<!-- hold:<host>:<epoch> -->` — authoritative; the issue's `updatedAt` moves on ANY activity and would mask a stale hold):

```bash
# List hold comments with their embedded timestamps
gh api --paginate "repos/{owner}/{repo}/issues/<N>/comments?per_page=100" --jq '[.[] | select(.body | startswith("<!-- hold:")) | {id, marker: (.body | split("-->")[0])}]' | tr -d '\r'
```

Release ONLY the individual hold comments older than 15 minutes via PATCH (preserves audit trail) — an issue can carry an abandoned hold AND a newer active one, and the active holder must keep its hold:

```bash
gh api --method PATCH "repos/{owner}/{repo}/issues/comments/<STALE_COMMENT_ID>" -f body="⏸ **Released** — hold lifted (reason: stale)"
```

Remove the `status:considering` label and post the released-for-pickup comment ONLY when no unreleased hold comments remain (writes):

```bash
gh issue edit <N> --remove-label "status:considering"
gh issue comment <N> --body "Released stale hold (no activity for >15min). Available for pickup."
```

### 2. Stale Claims

Issues with `status:claimed` label that haven't been updated in >24 hours (stale activity suggests abandoned work):

```bash
gh issue list --label "status:claimed" --state open --json number,title,assignees,updatedAt --limit 50 | tr -d '\r'
```

For stale claim detection, use GitHub search's date filtering to find issues not updated in >24 hours:

```bash
gh issue list --label "status:claimed" --search "updated:<$(date -u -d '24 hours ago' +%Y-%m-%d 2>/dev/null || date -u -v-1d +%Y-%m-%d)" --state open --json number,title,assignees,updatedAt --limit 50 | tr -d '\r'
```

Note: the `date` command differs between GNU (`-d '24 hours ago'`) and macOS BSD (`-v-1d`). If both fail, fall back to fetching all claimed issues and comparing `updatedAt` timestamps against the current time.

Before flagging, check each candidate for an active linked PR — a claim with an open PR under review is working, not stale (this is what the report's "no linked PR" column asserts):

```bash
gh pr list --search "<N> in:body" --state open --json number,title --limit 5 | tr -d '\r'
```

Exclude candidates with an open referencing PR. Present each remaining stale issue with assignee and last update time. Ask the user before releasing — the agent may still be working in another session.

**Action:** For stale claims, suggest (writes; explicit-login `--remove-assignee` is identity-agnostic):

```bash
gh issue edit <N> --remove-label "status:claimed" --remove-assignee <login>
gh issue comment <N> --body "Released stale claim (no activity for >24h). Available for pickup."
```

### 3. Orphaned Recurring Entries

Skip when the consuming repo has no `.github/recurring-schedule.json`. Only **due** entries
(`next_due <= today`) without a corresponding issue are orphan-suspect — a future-dated row legitimately
has no issue yet (recurring automation, or a `setup` seed, creates the issue only when the item becomes
due), so orphan-flagging every issue-less row would report healthy future rows as false orphans. This
mirrors the same gate in the `due` action.

```bash
# Due entries only — future rows are healthy without an issue
SCHEDULE="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.github/recurring-schedule.json"
cat "$SCHEDULE" | jq -r --arg today "$(date +%Y-%m-%d)" '
  .items[] | select(.next_due != null and .next_due <= $today) | .title'

# Get all recurring issues
gh issue list --label "recurring" --state all --json number,title --limit 100 | tr -d '\r'
```

Cross-reference: a **due** schedule item with no matching issue is orphaned. Note: recurring automation
titles issues as `[Maintenance] {title}`, so strip the prefix when comparing against schedule titles.

### 4. Unlabeled Issues

Open issues missing expected labels. Gate the `category:` check on the repo actually defining category labels — otherwise every issue would be flagged:

```bash
HAS_CATEGORY=$(gh label list --limit 200 --json name --jq '[.[].name | select(startswith("category:"))] | length' | tr -d '\r')

# Missing type: label (always checked)
gh issue list --state open --json number,title,labels --limit 100 --jq '
  [.[] | select(any(.labels[]; .name | startswith("type:")) | not)
   | {number, title, labels: [.labels[].name]}]
' | tr -d '\r'

# Missing category: label (only when HAS_CATEGORY > 0)
gh issue list --state open --json number,title,labels --limit 100 --jq '
  [.[] | select(any(.labels[]; .name | startswith("category:")) | not)
   | {number, title, labels: [.labels[].name]}]
' | tr -d '\r'
```

### 5. Duplicate Label Detection

Issues with conflicting labels (e.g., both `priority:p0-critical` and `priority:p3-low`):

```bash
gh issue list --state open --json number,title,labels --limit 100 --jq '
  [.[] | select(
    ([.labels[].name | select(startswith("priority:"))] | length) > 1
  ) | {number, title, priorities: [.labels[] | .name | select(startswith("priority:"))]}]
' | tr -d '\r'
```

## Output

```markdown
## Work-Item Audit

### Stale Claims (>24h, no linked PR)
| # | Issue | Assigned | Last Update | Action |
|---|-------|----------|-------------|--------|
| 1 | #42 Fix analyzer | @agent1 | 36h ago | Release? |

### Orphaned Recurring Entries
| # | Schedule Item | Status |
|---|--------------|--------|
| 1 | Review linter config | No matching issue |

### Unlabeled Issues
| # | Issue | Missing |
|---|-------|---------|
| 1 | #55 Something | No type:* label |

### Label Conflicts
(none found)

**Summary:** X stale claims, Y orphaned entries, Z unlabeled issues
```

## Notes

- The audit is read-only by default. It presents findings and suggests actions
- For each stale claim, ask the user before releasing (the agent may still be working in another session)
- Run periodically (weekly) or before the `work` action to keep the tracker clean
