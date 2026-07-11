# settings-audit — Phase 2 validation categories

Detailed checks for each Phase 2 category (A–G). SKILL.md Phase 2 names the categories + points here;
this file carries the per-check criteria. Run each category's checks and record findings with severity
ratings.

Load the audit checklist alongside these: [audit-checklist.md](../reference/audit-checklist.md).

## Category A: Schema & Structure

- `$schema` present and points to `https://json.schemastore.org/claude-code-settings.json`
- No unknown top-level keys (cross-reference against official docs schema)
- `settings.local.json` does NOT contain `mcpServers` (wrong file — use `.mcp.json`)

## Category B: Permissions

- **Baseline permission patterns**: iterate the patterns in
  [required-permissions.md](../reference/required-permissions.md) — each pattern in
  `sensitive-file-deny` and `destructive-bash-deny` must appear in `settings.json` `permissions.deny`;
  each pattern in `ask-rules` must appear in `settings.json` `permissions.ask`. When the consuming
  repo's own rules declare additional required patterns, check those too
- **Deny rules in settings.json ONLY** — not in settings.local.json (bug [#8961](https://github.com/anthropics/claude-code/issues/8961))
- **No deprecated `:*` syntax** in any permission rule (check all three arrays)
- **No overly broad patterns** — `Bash(git *)` should be split into specific operations
- **Evaluation order** makes sense — deny overrides ask overrides allow

## Category C: MCP Servers

- All stdio server commands resolve (check `which` or `command -v` for the binary)
- If the repo wraps npx-based MCP servers with a launcher script (Windows cross-platform spawn
  workaround per CC issue [#36808](https://github.com/anthropics/claude-code/issues/36808)), every
  npx-based server entry references the same launcher path AND the launcher file exists and is
  readable. Repos without a launcher convention skip this check
- Env var references use `${VAR_NAME}` syntax (not bare `$VAR`)
- `disabledMcpjsonServers` entries match actual server names in `.mcp.json`
- Disabled servers have a documented reason (cross-reference the repo's MCP server convention docs when present)
- HTTP-type servers have valid URL patterns

## Category D: Hooks

- All hook script paths resolve to existing files on disk
- Scripts are readable (not permission-denied)
- Timeouts are reasonable: 5-15s for simple formatters, 30s for slow-startup tools (pwsh)
- Matchers use valid regex syntax
- `$CLAUDE_PROJECT_DIR` references are properly quoted in commands
- No duplicate hooks (same script registered twice for same event)
- Hook events are valid (cross-reference against official docs)

## Category E: Plugins

Two layers:

**E.1 Static checks**:

- Enabled plugins belong to an installed marketplace in `extraKnownMarketplaces`
- No references to plugins from unknown/uninstalled marketplaces
- Explicitly disabled plugins are intentional (not stale entries from removed marketplaces)

**E.2 Upstream drift detection** (live network — `scripts/check-plugin-drift.sh`):

Compares `enabledPlugins` keys against live `marketplace.json` for each registered marketplace.
Detects three drift modes static checks miss:

| Mode | Definition | Auto-fix policy |
|---|---|---|
| **ORPHAN** (false) | Plugin in `enabledPlugins` set to `false`, NOT in upstream catalog | AUTO-REMOVE — behaviorally a no-op (`false` ≡ absent for plugin loading) and the entry generates `/doctor` errors |
| **ORPHAN** (true) | Plugin in `enabledPlugins` set to `true`, NOT in upstream catalog | REPORT ONLY — user explicitly enabled a plugin that is now gone upstream; surface for manual review, never auto-remove |
| **NEW** | Plugin in upstream catalog, NOT in `enabledPlugins` | AUTO-ADD as `enabledPlugins["<name>@<market>"]: false` — records the discovery as an explicit opt-out, which keeps per-developer `settings.local.json` overrides functional |
| **RENAME?** | Heuristic match between an ORPHAN and a NEW within the same marketplace | REPORT ONLY — flag for human review, no automation |

**Network-tolerant**: a marketplace whose upstream fetch fails is reported `SKIP` and does not fail
the run. Use `SETTINGS_AUDIT_FIXTURE_DIR=<dir>` to short-circuit network calls in tests (loads
`<market-key>.json` from the fixture directory).

**Invocation:**

```bash
# Project audit (default — reads .claude/settings.json at the project root)
bash "${CLAUDE_PLUGIN_ROOT}/skills/settings-audit/scripts/check-plugin-drift.sh"

# User audit (override target file)
CLAUDE_SETTINGS_FILE=~/.claude/settings.json \
  bash "${CLAUDE_PLUGIN_ROOT}/skills/settings-audit/scripts/check-plugin-drift.sh"

# Plan + dry-run apply
bash "${CLAUDE_PLUGIN_ROOT}/skills/settings-audit/scripts/fix-plugin-drift.sh"

# Apply auto-fixes
bash "${CLAUDE_PLUGIN_ROOT}/skills/settings-audit/scripts/fix-plugin-drift.sh" --yes
```

**Env var contract:**

| Env var | Purpose | Default |
|---|---|---|
| `CLAUDE_SETTINGS_FILE` | Path to the `settings.json` to audit | `<project>/.claude/settings.json` |
| `SETTINGS_AUDIT_FIXTURE_DIR` | Test fixture directory (skips network) | unset |
| `SETTINGS_AUDIT_OUTPUT_JSON` | Path to write structured findings JSON | unset (stdout only) |

## Category F: Environment Variables

- Env vars in `settings.json` are documented Claude Code variables or justified custom vars
- Secrets (tokens, keys, passwords) are in `settings.local.json`, NOT in `settings.json`
- Path-based env vars (cloud-CLI config dirs, tool-cache paths) use forward slashes for cross-platform portability

## Category G: Skill-listing budget

- **Overflow check** — if `/doctor` reports dropped skill descriptions, the skill listing has exceeded
  its budget and the least-invoked skills' trigger keywords are silenced (names still resolve;
  auto-invocation degrades silently). `/doctor` needs an interactive TTY — prompt the user to run it.
  Repos with large skill rosters overflow routinely
- **Levers, cheapest first** — trim `description` / `when_to_use` frontmatter (key use case first;
  1,536-char cap per entry), `skillOverrides: { <skill>: "name-only" }` in a contributor's
  `settings.local.json` (does NOT apply to plugin skills), then `skillListingBudgetFraction` /
  `SLASH_COMMAND_TOOL_CHAR_BUDGET` in project settings as a last resort (costs context every turn)
- **Recommend, don't apply the list** — `skillOverrides` is contributor-scoped; surface the candidate
  least-invoked skills, leave the actual name-only list to the developer
