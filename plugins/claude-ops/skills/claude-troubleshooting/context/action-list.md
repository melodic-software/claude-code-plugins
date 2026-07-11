# Action: `list`

**Usage:** `/claude-troubleshooting list [--category <cat>] [--status <status>]`

Show all tracked issues from registry, grouped by status and category.

## Output format

```markdown
## Issue Registry: N tracked issues

### Blocking (N)

| # | Repo | Title | Feature | Workaround | Blocked Work |
|---|------|-------|---------|------------|--------------|
| #NNNNN | repo | Title | Feature | Workaround | What's blocked |

### Degraded (N)

(same format)

### Fixed (awaiting follow-up) (N)

| # | Repo | Title | Resolved | Follow-Up Status |
|---|------|-------|----------|-----------------|
| #NNNNN | repo | Title | Date | follow-up item exists? |
```
