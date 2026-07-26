# audit — procedures & fix policy

Operational recipes the SKILL.md phases point to: how to inspect `settings.local.json` without leaking
secrets (Phase 1), and which findings the skill may auto-fix vs which need judgment (Phase 5).

## Reading settings.local.json safely

Treat the file as secret-bearing regardless of deny rules. Run `check-structure.sh` first;
supplemental jq: below.

The safety here is *what gets emitted*, not what gets opened. `check-structure.sh` opens the file from
inside a subprocess, which a `Read(...)` deny does not cover — it is safe because it emits counts and
never values. The `cat … | jq` recipes below go the other way: `cat` is a file command Claude Code
recognizes in Bash, so a project carrying the baseline `Read(./.claude/settings.local.json)` deny will
block them. That is the correct outcome — do not route around it with an interpreter one-liner
(`python -c`, `node -e`) to dump content the sanctioned script will not emit. See "Scope of a Read
deny" in [reference/required-permissions.md](../reference/required-permissions.md).

**Counts are not guaranteed.** Where the project also enables the sandbox, the baseline `Read` deny
merges into the sandbox filesystem boundary and the OS blocks `check-structure.sh` and its `tr`/`jq`
children too — the subprocess route closes. The script distinguishes that case: it reports
`Readable: no` with a `not inspectable` note rather than `Valid JSON: no`, and does not fail the run.
Treat that output as the answer. Record the file as not inspectable under the project's own
configuration, carry that into the report, and do not escalate to another reader to get the counts
anyway. A `Present: yes` / `Readable: no` pair is a correct result, not a broken audit.

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
