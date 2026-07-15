# Settings Audit Checklist

Validation rules organized by category. Each check has a severity, what to look for, and how to verify.

## A. Schema & Structure

| Check | Severity | How to verify |
| --- | --- | --- |
| All config files are valid JSON | error | `jq . <file>` exits 0 |
| `$schema` present in settings.json | warning | `jq '."$schema"'` returns URL |
| `$schema` URL is `https://json.schemastore.org/claude-code-settings.json` | warning | Exact string match |
| No `mcpServers` key in settings.json or settings.local.json | error | `jq '.mcpServers // empty'` — MCP defs go in `.mcp.json` |
| settings.local.json does not contain `hooks` (team config, not personal) | info | `jq '.hooks // empty'` |

## B. Permissions

### B.1 / B.2 / B.3 Baseline permission patterns

Iterate the baseline patterns in [required-permissions.md](required-permissions.md); assert presence
per sub-category:

| Sub-category | Target array in `settings.json` | Severity |
| --- | --- | --- |
| `sensitive-file-deny` | `permissions.deny` (Read patterns) | error |
| `destructive-bash-deny` | `permissions.deny` (Bash patterns) | error |
| `ask-rules` | `permissions.ask` (Bash patterns) | warning |

The baseline covers the cross-repo security floor (sensitive `.env*` / `secrets/**` /
`settings.local.json`; destructive `git push --force` / `git push -f` / `git reset --hard` /
`git clean` families; ask on `git push`). Projects that document additional required patterns in their
own rules (extra secret-file paths, destructive API-endpoint families, hook-bypass blockers,
additional ask-gates) get those checked at the same severities.

### B.4 Syntax checks

| Check | Severity | How to verify |
| --- | --- | --- |
| No deprecated `:*` syntax in any permission rule | warning | `jq -r '.permissions \| to_entries[] \| .value[]' \| grep ':*'` |
| Deny rules are in settings.json, NOT settings.local.json | error | Bug [#8961](https://github.com/anthropics/claude-code/issues/8961) — deny rules in local are silently ignored |
| No blanket `Bash(git *)` in allow (too broad) | warning | Should be split into specific git operations |

### B.5 Completeness

| Check | Severity | How to verify |
| --- | --- | --- |
| `git commit` is in allow list | warning | Needed for standard commit workflow |
| `git fetch` is in allow list | info | Needed for branch updates |
| `git stash` is in allow list | info | Needed for context switching |

## C. MCP Servers

### C.1 Server command validity

| Check | Severity | How to verify |
| --- | --- | --- |
| stdio server commands resolve on PATH | error | `command -v <cmd>` for each server's command |
| If the repo wraps npx-based MCP servers with a launcher script (Windows cross-platform spawn workaround per CC issue [#36808](https://github.com/anthropics/claude-code/issues/36808)), every npx-based server entry references the same launcher path | error | Check args[0] across npx-using entries — all should point at the same launcher; skip if no launcher convention |
| The launcher script file exists and is readable | error | `[[ -f <launcher-path> ]]` when one is referenced |
| HTTP servers have valid URL patterns | warning | URL is well-formed |

### C.2 Env var references

| Check | Severity | How to verify |
| --- | --- | --- |
| Env vars use `${VAR_NAME}` syntax | warning | Check `.mcp.json` env blocks for bare `$VAR` |
| Required env vars are documented | info | Cross-reference env blocks against settings.local.json env keys |

### C.3 Server status

| Check | Severity | How to verify |
| --- | --- | --- |
| `enableAllProjectMcpServers` is `false` | error | Allowlist pattern — new `.mcp.json` servers must be explicitly approved |
| `enabledMcpjsonServers` + `disabledMcpjsonServers` cover all `.mcp.json` servers | error | `comm -23 <(jq -r '.mcpServers\|keys[]' .mcp.json \| sort) <(jq -r '(.enabledMcpjsonServers + .disabledMcpjsonServers)[]' .claude/settings.json \| sort)` must be empty |
| `disabledMcpjsonServers` entries match actual server names | error | Every entry in the array must be a key in `.mcp.json` `mcpServers` |
| `enabledMcpjsonServers` entries match actual server names | error | Every entry in the array must be a key in `.mcp.json` `mcpServers` |
| Disabled servers have documented reason | info | Cross-reference the repo's MCP server convention docs when present |
| No orphaned servers (defined but never referenced in permissions) | info | Server tools in `.mcp.json` should have corresponding `mcp__<name>__*` in allow |

## D. Hooks

| Check | Severity | How to verify |
| --- | --- | --- |
| All hook scripts exist on disk | error | Resolve `$CLAUDE_PROJECT_DIR` to the project root, check file exists |
| Hook scripts are readable | error | `[[ -r <path> ]]` |
| Timeouts are reasonable (5-30s for formatters, up to 60s for heavy tools) | warning | Compare against known good values |
| Matchers are valid regex | warning | `echo "" \| grep -P '<matcher>' 2>/dev/null` or check syntax |
| Command hooks use quoted shell form | warning | Pattern: `"command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/..."`, **no `args`**; the `"command":"bash"`+`args` (exec-form) variant backslash-mangles `${CLAUDE_PROJECT_DIR}` on native Windows |
| No duplicate hooks (same script registered twice for same event) | info | Compare commands within each event |
| Hook events are valid per official docs | error | Cross-reference against the [hooks reference](https://code.claude.com/docs/en/hooks) — fetch it live rather than trusting a recalled event list |

## E. Plugins

| Check | Severity | How to verify |
| --- | --- | --- |
| Every plugin's marketplace exists in `extraKnownMarketplaces` | error | Split `@marketplace` suffix, verify marketplace key exists |
| Explicitly disabled plugins are intentional | info | Review false entries — are they stale or deliberately off? |
| No plugins from incompatible marketplaces (Agent Skills format) | error | Repos with only root `marketplace.json` but no per-plugin `plugin.json` are incompatible |

## F. Environment Variables

| Check | Severity | How to verify |
| --- | --- | --- |
| Env vars in settings.json are documented CC vars | warning | **MANDATORY**: fetch `code.claude.com/docs/en/env-vars` and search for each env var name. WebSearch alone is insufficient — the official page is the authoritative source. Do NOT flag any env var as "unrecognized" without first checking this page |
| No secrets in settings.json (tokens, keys, passwords) | error | Scan for patterns: `ghp_`, `eyJ`, `sk-`, `AKIA`, common token prefixes |
| Secrets are in settings.local.json only | error | settings.local.json is gitignored |
| Path-based env vars use forward slashes | info | Windows compatibility |
