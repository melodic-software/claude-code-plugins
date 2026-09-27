# audit Checklist

Copy into your working task notes. Tick as each phase completes.

## Phases

- [ ] Phase 1: Run the engine. It records `claude --version`, fetches `settings-reference` and `env-vars` through `llms.txt` (network; `--docs-dir` reuses pages on disk), and reads `.claude/settings.json` + `settings.local.json` + `.mcp.json`; check its `docs` coverage record for unread pages. Machine-scope managed settings: structure only, via `check-structure.sh`
- [ ] Phase 2: Validate. Schema check; permission rule correctness; hook event names; `enabledPlugins` boolean values; `enableAllProjectMcpServers` semantics
- [ ] Phase 3: Research & recheck. The pages the engine did not read: fetch the cited pages verbatim, run `check-doc-citations.sh --docs-dir`, compare against `settings-reference` and `settings`; recheck known issues by the degrade ladder
- [ ] Phase 4: Report. Categorized findings (correctness / drift / issue-affected / convention-conflict)
- [ ] Phase 5: Fix (only with `--fix` flag). Apply Phase 4 findings; verify config files still valid JSON

## Skip criteria

- Phase 5 SKIPPED in default report-only mode (must explicitly `--fix` to opt in)
- Offline: the engine reports its unfetched pages `unread` and their rows `not-inspectable`, and the Phase 3 fetch is SKIPPED; note both gaps in the report
