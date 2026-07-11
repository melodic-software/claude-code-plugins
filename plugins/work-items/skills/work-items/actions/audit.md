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

For each issue, check if the hold is older than 15 minutes by comparing `updatedAt`. If stale (writes):

```bash
# Remove the stale considering label
gh issue edit <N> --remove-label "status:considering"
# Find stale hold comments to release
gh api "repos/{owner}/{repo}/issues/<N>/comments" --jq '[.[] | select(.body | startswith("<!-- hold:")) | .id]' | tr -d '\r'
# Release each stale hold comment via PATCH (preserves audit trail)
gh api --method PATCH "repos/{owner}/{repo}/issues/comments/<COMMENT_ID>" -f body="⏸ **Released** — hold lifted (reason: stale)"
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

Present each stale issue with assignee and last update time. Ask the user before releasing — the agent may still be working in another session.

**Action:** For stale claims, suggest (writes; explicit-login `--remove-assignee` is identity-agnostic):

```bash
gh issue edit <N> --remove-label "status:claimed" --remove-assignee <login>
gh issue comment <N> --body "Released stale claim (no activity for >24h). Available for pickup."
```

### 3. Orphaned Recurring Entries

Skip when the consuming repo has no `.github/recurring-schedule.json`. Entries in the schedule that have no corresponding open or recently-closed issue:

```bash
# Get all recurring titles from schedule
cat .github/recurring-schedule.json | jq -r '.items[].title'

# Get all recurring issues
gh issue list --label "recurring" --state all --json number,title --limit 100 | tr -d '\r'
```

Cross-reference: schedule items without a matching issue are orphaned. Note: recurring automation titles issues as `[Maintenance] {title}`, so strip the prefix when comparing against schedule titles.

### 4. Unlabeled Issues

Open issues missing expected labels (no `type:*` label, no `category:*` label — skip the `category:` check when the repo defines no category labels):

```bash
gh issue list --state open --json number,title,labels --limit 100 --jq '
  [.[] | select(
    (any(.labels[]; .name | startswith("type:")) | not) or
    (any(.labels[]; .name | startswith("category:")) | not)
  ) | {number, title, labels: [.labels[].name]}]
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
