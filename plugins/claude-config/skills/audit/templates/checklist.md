# audit Checklist

Copy into your working task notes. Tick as each phase completes.

## Phases

- [ ] Phase 1: Load & parse — read `.claude/settings.json` + `settings.local.json` + `.mcp.json` + machine-scope managed settings (structure only, via `check-structure.sh`)
- [ ] Phase 2: Validate — schema check; permission rule correctness; hook event names; `enabledPlugins` boolean values; `enableAllProjectMcpServers` semantics
- [ ] Phase 3: Research & recheck — fetch the cited pages verbatim, run `check-doc-citations.sh --docs-dir`, compare against `settings-reference` and `settings`; recheck known issues by the degrade ladder
- [ ] Phase 4: Report — categorized findings (correctness / drift / issue-affected / convention-conflict)
- [ ] Phase 5: Fix (only with `--fix` flag) — apply Phase 4 findings; verify config files still valid JSON

## Skip criteria

- Phase 5 SKIPPED in default report-only mode (must explicitly `--fix` to opt in)
- Phase 3 upstream-doc fetch SKIPPED when offline; note the gap in the report
