# mcp-tool-audit checklist

Keep this as an in-response tracker for a multi-server run; tick each phase as it completes.

## Phases

- [ ] Phase 1: Discover servers and tools — run `bash "${CLAUDE_PLUGIN_ROOT}/skills/mcp-tool-audit/scripts/discover.sh"` (or `--path <dir>` to scope to one server)
- [ ] Phase 2: Evaluate against checklist — per-tool criteria C1-C16 per `reference/checklist.md` (description, parameters, naming, annotations, granularity, schema)
- [ ] Phase 3: Report — per-tool verdict (PASS / WARN / FAIL) with concrete improvement suggestions

## Skip criteria

- Phase 1 whole-project enumeration is scoped when an explicit `--path <dir>` narrows the scan.
- Phase 2 may run subagent fan-out for ≥5 tools.
