---
description: Search Claude Code GitHub issues for troubleshooting. Shortcut for searching anthropics/claude-code.
argument-hint: <search-terms> [--label <label>] [--state open|closed|all] [--format compact|table|detailed]
allowed-tools: Bash, Read, Grep, WebFetch, WebSearch
---

# Search Claude Code Issues

Shortcut command to search issues in the Claude Code repository (anthropics/claude-code).

## Usage

```text
/claude-ecosystem:search-claude-issues path doubling
/claude-ecosystem:search-claude-issues hooks error --label bug
/claude-ecosystem:search-claude-issues "MCP timeout" --state open
```

## Arguments

- **Search terms**: Keywords to search for (required)
- **--label**: Filter by label (optional, can be repeated)
- **--state**: Filter by state: open, closed, or all (default: all)
- **--format**: Output format: compact, table, or detailed (default: compact)
- **--limit**: Maximum results (default: 15)

## Workflow

This command is a shortcut that:

1. Sets repository to `anthropics/claude-code` automatically
2. Invokes the `github-issues` skill with provided search terms
3. Returns formatted results

Equivalent to: `/git:search-issues anthropics/claude-code <search-terms>`

## Examples

### Search for Hook Issues

```text
/claude-ecosystem:search-claude-issues hooks PreToolUse
```

### Search for Bug Reports

```text
/claude-ecosystem:search-claude-issues memory leak --label bug
```

### Search Open Issues Only

```text
/claude-ecosystem:search-claude-issues "context window" --state open
```

### Get Detailed Output

```text
/claude-ecosystem:search-claude-issues "path doubling" --format detailed
```

## Common Claude Code Labels

- **bug** - Bug reports
- **enhancement** - Feature requests
- **hooks** - Hook-related issues
- **mcp** - MCP server issues
- **documentation** - Documentation improvements
- **good first issue** - Beginner-friendly issues

## Output Formats

### Compact (default)

```text
#11984 [open] Path doubling in PowerShell hooks (bug, hooks)
#11523 [closed] Fix memory leak in long sessions (bug, fixed)
```

### Table

```markdown
| # | State | Title | Labels |
|---|-------|-------|--------|
| 11984 | open | Path doubling in PowerShell hooks | bug, hooks |
```

### Detailed

```markdown
### #11984 - Path doubling in PowerShell hooks
**State:** open | **Labels:** bug, hooks | **Created:** 2024-12-01
**URL:** https://github.com/anthropics/claude-code/issues/11984

When using cd && in PowerShell, paths get doubled...

**Workaround:** Use absolute paths instead of cd &&
```

## Related

- `/git:search-issues` - Search any GitHub repository
- `claude-code-issue-researcher` agent - Autonomous issue research
- `github-issues` skill - Underlying skill for all issue operations
