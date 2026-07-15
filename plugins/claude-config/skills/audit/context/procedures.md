# audit — procedures & fix policy

Operational recipes the SKILL.md phases point to: how to inspect `settings.local.json` without leaking
secrets (Phase 1), and which findings the skill may auto-fix vs which need judgment (Phase 5).

## Reading settings.local.json safely

Treat the file as secret-bearing regardless of deny rules. Run `check-structure.sh` first;
supplemental jq: below.

```bash
# Key inventory (no values)
cat .claude/settings.local.json | tr -d '\r' | jq 'keys'

# Permission count
cat .claude/settings.local.json | tr -d '\r' | jq '{
  env_keys: (.env | keys),
  allow_count: (.permissions.allow // [] | length),
  deny_count: (.permissions.deny // [] | length),
  ask_count: (.permissions.ask // [] | length),
  plugin_count: (.enabledPlugins // {} | length)
}'

# Check for deny rules (should NOT be here per bug #8961)
cat .claude/settings.local.json | tr -d '\r' | jq '.permissions.deny // empty'
```

## Phase 5 — fixes the skill can apply

| Category | Auto-fixable | Requires judgment |
| --- | --- | --- |
| Add `$schema` | Yes | No |
| Fix deprecated `:*` syntax | Yes | No |
| Add missing baseline deny rules | Yes (from checklist) | No |
| Move deny rules from local to project | Yes | No |
| Add new settings from docs | No | Yes (evaluate relevance) |
| Restructure permissions | No | Yes (evaluate scope) |
| Fix MCP server config | No | Yes (may need env vars) |
| Remove orphan plugins (`false`) | Yes (`scripts/fix-plugin-drift.sh --yes`) | No |
| Add new upstream plugins as `false` | Yes (`scripts/fix-plugin-drift.sh --yes`) | No |
| Remove orphan plugins (`true`) | No | Yes (user enabled a now-removed plugin — investigate intent) |
| Rename plugins (heuristic match) | No | Yes (verify upstream rename, update key, preserve `enabled` value) |
