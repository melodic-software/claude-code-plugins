# audit Checklist

Copy into your working task notes. Tick as each phase completes.

## Phases

- [ ] Phase 1: Load & parse — read `.claude/settings.json` + `settings.local.json` + `.mcp.json` + managed settings if present
- [ ] Phase 2: Validate — schema check; permission rule correctness; hook event names; `enabledPlugins` boolean values; `enableAllProjectMcpServers` semantics
- [ ] Phase 3: Research & recheck — verify against upstream docs (`code.claude.com/docs/en/settings`); recheck known issues
- [ ] Phase 4: Report — categorized findings (correctness / drift / issue-affected / convention-conflict)
- [ ] Phase 5: Fix (only with `--fix` flag) — apply Phase 4 findings; verify config files still valid JSON

## Skip criteria

- Phase 5 SKIPPED in default report-only mode (must explicitly `--fix` to opt in)
- Phase 3 upstream-doc fetch SKIPPED when offline; note the gap in the report
