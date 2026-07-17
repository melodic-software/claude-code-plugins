# Action: `check-all`

**Usage:** `/known-issues check-all`

Check every registry issue against current GitHub status. Primary purpose: find issues RESOLVED since last check — unblocked work needing follow-up.

## Process

1. Read `registry.json`
2. For each tracked issue, check current status via `gh issue view <number> --repo <repo> --json state,title,closedAt,stateReason`
3. Compare current state to tracked state
4. For newly resolved issues:
   - Update `registry.json`: `--status closed --closedAt <GitHub closedAt>` and re-categorize
     to `--category fixed` (`fixed` is a category; `status` only accepts `open`/`closed`)
   - Identify what was blocked (from `blocked_work` field)
   - Identify what docs need updating (from `affected_files` field)
   - Propose a follow-up work item for each action (file with the consumer's tracker — e.g. `gh issue create` — after user confirmation):
     - "Update `<affected_file>` — issue #NNNNN (`<title>`) is now resolved. Remove workaround, update documentation, and implement/enable the previously blocked feature."
   - Present summary of what changed

## Output format

```markdown
## Registry Check: N issues checked

### Newly Resolved (action needed)

| # | Title | Resolved | Blocked Work | Follow-Up |
|---|-------|----------|--------------|-----------|
| #NNNNN | Title | Date | What was blocked | follow-up item filed |

### Still Open

| # | Title | Category | Last Checked |
|---|-------|----------|--------------|
| #NNNNN | Title | blocking | YYYY-MM-DD |

### No Change

N issues unchanged since last check.
```
