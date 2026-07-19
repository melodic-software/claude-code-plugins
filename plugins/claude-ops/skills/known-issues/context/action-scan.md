# Action: `scan`

**Usage:** `/known-issues scan` (report-only) · `/known-issues scan --add` (also register)

Grep the entire repo for GitHub issue references (pattern: `#NNNNN` with
`github.com/anthropics` or `github.com/microsoft/mcp` context) and report the ones not in
the registry. Per the naming doctrine's verb contract, bare `scan` is **read-only**: it
finds, cross-references, and reports. Registering the findings mutates the registry and
therefore requires the explicit `--add` override.

## Process

1. Search via `grep -rn 'github\.com/anthropics/[^/]*/issues/[0-9]*' . --include='*.md' --include='*.sh' --include='*.json'` (also search `microsoft/mcp`)
2. Search bare references in likely surfaces (adapt to the consumer repo): `grep -rn '#[0-9]\{4,5\}' .claude/ docs/ CLAUDE.md --include='*.md'`
3. Parse unique issue numbers and repos
4. Cross-reference with `registry.json` — identify issues NOT yet tracked
5. **Bare `scan` stops here**: report untracked references (with `gh issue view` metadata
   where cheap) and print the exact `scan --add` invocation that would register them.
6. **With `--add` only**: for each new issue, fetch metadata via `gh issue view` and add to
   the registry, then present what was added.

## Output format

```markdown
## Repo Scan: N issue references found

### Already Tracked: M issues

### Untracked: K issues (run `scan --add` to register)

| # | Repo | Title | Category | Found In |
|---|------|-------|----------|----------|
| #NNNNN | anthropics/claude-code | Title | blocking | docs/some-file.md:L42 |

### Orphaned References (issue doesn't exist or inaccessible)

| Reference | Found In | Action |
|-----------|----------|--------|
| #99999 | file.md:L10 | Remove reference or verify issue number |
```

With `--add`, the "Untracked" section becomes "Newly Added" and reports the registry write.
