# Action: `scan`

**Usage:** `/claude-troubleshooting scan`

Grep entire repo for GitHub issue references (pattern: `#NNNNN` with `github.com/anthropics` or `github.com/microsoft/mcp` context) and add ones not in registry.

## Process

1. Search via `grep -rn 'github\.com/anthropics/[^/]*/issues/[0-9]*' . --include='*.md' --include='*.sh' --include='*.json'` (also search `microsoft/mcp`)
2. Search bare references in likely surfaces (adapt to the consumer repo): `grep -rn '#[0-9]\{4,5\}' .claude/ docs/ CLAUDE.md --include='*.md'`
3. Parse unique issue numbers and repos
4. Cross-reference with `registry.json` — identify issues NOT yet tracked
5. For each new issue, fetch metadata via `gh issue view` and add to registry
6. Present summary of what was found and added

## Output format

```markdown
## Repo Scan: N issue references found

### Already Tracked: M issues

### Newly Added: K issues

| # | Repo | Title | Category | Found In |
|---|------|-------|----------|----------|
| #NNNNN | anthropics/claude-code | Title | blocking | docs/some-file.md:L42 |

### Orphaned References (issue doesn't exist or inaccessible)

| Reference | Found In | Action |
|-----------|----------|--------|
| #99999 | file.md:L10 | Remove reference or verify issue number |
```
