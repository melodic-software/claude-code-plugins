---
description: Search GitHub issues in any repository. Find bugs, features, and discussions.
argument-hint: <owner/repo> <search-terms> [--label <label>] [--state open|closed|all] [--format compact|table|detailed]
allowed-tools: Bash, Read, Grep, WebFetch, WebSearch
---

# Search GitHub Issues

Search for issues in any GitHub repository using the `github-issues` skill.

## Usage

```text
/git:search-issues anthropics/claude-code path doubling
/git:search-issues owner/repo "error message" --label bug
/git:search-issues owner/repo feature request --state open
```

## Arguments

- **First argument**: Repository in `owner/repo` format (required)
- **Remaining arguments**: Search terms (required)
- **--label**: Filter by label (optional, can be repeated)
- **--state**: Filter by state: open, closed, or all (default: all)
- **--format**: Output format: compact, table, or detailed (default: compact)
- **--limit**: Maximum results (default: 15)

## Workflow

1. **Parse arguments** - Extract repo, search terms, and options
2. **Invoke github-issues skill** - Use the skill's query patterns
3. **Check gh CLI availability** - Fall back to web if unavailable
4. **Execute search** - Run appropriate search command
5. **Format results** - Apply requested output format
6. **Report findings** - Display results to user

## Examples

### Basic Search

```text
/git:search-issues anthropics/claude-code hooks
```

Searches all issues (open and closed) for "hooks".

### Search with Label Filter

```text
/git:search-issues anthropics/claude-code memory leak --label bug
```

Searches for "memory leak" issues with the "bug" label.

### Open Issues Only

```text
/git:search-issues anthropics/claude-code feature request --state open
```

Searches only open issues.

### Detailed Output

```text
/git:search-issues anthropics/claude-code "path doubling" --format detailed
```

Returns full issue details including descriptions and workarounds.

## Output Formats

### Compact (default)

```text
#11984 [open] Path doubling in PowerShell hooks (bug, hooks)
#11523 [closed] Fix memory leak in long sessions (bug, fixed)
#10892 [open] Add custom status line support (enhancement)
```

### Table

```markdown
| # | State | Title | Labels |
|---|-------|-------|--------|
| 11984 | open | Path doubling in PowerShell hooks | bug, hooks |
| 11523 | closed | Fix memory leak in long sessions | bug, fixed |
```

### Detailed

```markdown
### #11984 - Path doubling in PowerShell hooks
**State:** open | **Labels:** bug, hooks | **Created:** 2024-12-01
**URL:** https://github.com/anthropics/claude-code/issues/11984

When using cd && in PowerShell, paths get doubled causing script failures...

**Workaround:** Use absolute paths instead of cd &&
```

## Error Messages

### Missing repository

```text
Error: Repository not specified.
Usage: /git:search-issues <owner/repo> <search-terms>
Example: /git:search-issues anthropics/claude-code hooks
```

### Missing search terms

```text
Error: No search terms provided.
Usage: /git:search-issues <owner/repo> <search-terms>
Example: /git:search-issues anthropics/claude-code "error message"
```

### gh CLI not available

```text
Note: GitHub CLI (gh) not installed. Using web search fallback.
Results may be less accurate. Install gh for better results: https://cli.github.com/
```

## Notes

- Uses `github-issues` skill for search logic
- Prefers gh CLI when available, falls back to web search
- For complex investigations, consider using the `issue-researcher` agent
