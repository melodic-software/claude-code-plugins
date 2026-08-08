# Settings Audit Checklist

Validation rules organized by category. Each check has a severity, what to look for, and how to verify.

Category G (skill-listing budget) has no table here — its checks are procedural and live in
[context/validation-categories.md](../context/validation-categories.md), which carries every
category's criteria.

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
| `timeout` is a seconds value, not milliseconds | warning | The [hooks reference](https://code.claude.com/docs/en/hooks) states for `timeout`: "Seconds before canceling. Defaults: 600 for `command`, `http`, and `mcp_tool`; 30 for `prompt`; 60 for `agent`." Any `timeout > 600` is almost certainly a millisecond figure — likely copied from the Bash/PowerShell tool's `tool_input.timeout`, which *is* documented in milliseconds on the same page. `120000` read as seconds is ~33 h |
| Timeouts are reasonable (5-30s for formatters, up to 60s for heavy tools) | warning | Compare against known good values |
| Matcher takes its intended evaluation path | warning | Classify the matcher by its characters, confirm exact-match vs regex matches intent, anchor regex-path matchers with `^…$` |
| Shell-form path placeholders are quoted | warning | Same page: "Prefer exec form for any hook that references a path placeholder. In shell form, wrap each placeholder in double quotes." Flag a shell-form hook whose project/plugin placeholder is unquoted, in **either** spelling — braced (`${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`) or bare-dollar (`$CLAUDE_PROJECT_DIR`), since both reach the shell and an unquoted path breaks on a space either way. Report exec form as the page's preference, but do **not** flag shell form itself — the page endorses omitting `args` when the hook needs pipes, `&&`, redirects, or a `.cmd`/`.bat` shim, and quoted shell form is a documented, correct spelling |
| Exec-form `command` resolves on every platform the repo targets | error | Same page: "On Windows, exec form requires `command` to resolve to a real executable such as a `.exe`." Windows-only constraint — `bash` and `sh` are real executables on macOS/Linux, so flag only for a repo that runs on Windows. There `bash` resolves to the WSL relay `System32\bash.exe` and the launch fails; a failed launch is a non-blocking error, so a gate hook silently enforces nothing. Fixes per the page: a real binary plus the script path in `args` (`"command": "node"`), or shell form with `"shell": "bash"`, which Claude Code routes through Git Bash instead of a PATH lookup |
| Shell-form PowerShell hooks avoid the bare `$CLAUDE_PROJECT_DIR` spelling | warning | Same page: "Don't write the bare `$CLAUDE_PROJECT_DIR` spelling in a PowerShell hook. PowerShell parses it as an undefined local variable and resolves it to `$null`". Use `${CLAUDE_PROJECT_DIR}` or `$env:CLAUDE_PROJECT_DIR` |
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

## H. Model and effort settings

Each check reads a settings file this skill already opens, and each detects a value the harness
accepts into the file and then does not apply the way its author expects. How loudly that surfaces
differs per row, so each row says so rather than the section claiming a blanket silence.

Two of these rows also have an authoring-time path: the declared schema section A checks for
constrains `effortLevel` by `enum` and `fallbackModel` by `maxItems`, so an editor validating
against it flags them before the file is ever loaded. The rows stay, because the schema is advisory
— the harness still reads a file that violates it — and because section A checks that `$schema` is
present, not what the values are. Where the schema and the harness disagree, the row says which is
which.

Apply `jq` recipes to `settings.json` and `~/.claude/settings.json`. For `settings.local.json`,
follow this skill's safe-read rule and go through `check-structure.sh`, which reports these keys by
value — `Effort level`, `Fallback chain` (raw and post-dedup counts), `Fallback entries` in order,
`Available models`, and `Enforce available models` — distinguishing `unset` from `(empty list)`
because those are different findings. Env and permission entries stay counts there, so a key that
lives only in the local file is still checkable without dumping the secrets beside it. Resolve
current behavior from <https://code.claude.com/docs/en/model-config> when the audit runs, the way
section F resolves environment variables against their own page.

| Check | Severity | How to verify |
| --- | --- | --- |
| `effortLevel` is not `max` or `ultracode` | warning | `jq '.effortLevel'`. Model configuration states both are session-only and "are not accepted here"; the declared schema's `enum` omits them too, so a schema-aware editor already flags this. Report what the author loses — the level they asked for is not the one that persists — without asserting which level runs instead, which the page does not state. `CLAUDE_CODE_EFFORT_LEVEL` is the durable route to `max` |
| `fallbackModel` satisfies both the declared `maxItems: 3` and the documented post-dedup cap | warning | These are two different tests and can disagree: the schema caps RAW array length at 3, while the page caps the chain "after duplicate removal", so `["sonnet","haiku","sonnet","opus"]` fails the schema at 4 entries but leaves exactly 3 after dedup. Report raw length over 3 as a schema violation, then dedupe in place with `jq '.fallbackModel \| reduce .[] as $m ([]; if index($m) then . else . + [$m] end)'` — `unique` would sort away the order the chain is tried in — and name any entry past the third as at risk of being ignored. Not "dead": allowlist-excluded entries are also dropped when the chain is read, and the page does not state whether that dropping happens before or after the cap |
| `availableModels` does not mix a family wildcard with a specific entry of that family | warning | An entry naming a specific model "disables that family's wildcard entry": `["sonnet", "claude-sonnet-4-5"]` permits only Sonnet 4.5, not every Sonnet. Reached the same way by a Mantle ID and by an `ANTHROPIC_CUSTOM_MODEL_OPTION` value embedding a family name. This one is not silent — an alias narrowed to an older permitted version shows "a notice naming both the requested and substituted models" — so the finding is that the allowlist is narrower than its author meant, not that nothing surfaces. Report the models they most likely still expect to be selectable |
| `enforceAvailableModels: true` is paired with a non-empty `availableModels` | error | `jq 'select(.enforceAvailableModels == true) \| .availableModels'` — the finding requires the flag to be `true` AND the list unset or empty. An explicit `false` is someone turning enforcement off on purpose and is never a finding, so gate on the value rather than the key's presence. When it does fire: the key "has no effect when `availableModels` is unset or empty", so an administrator who set it believes the Default option is constrained when it is not — an enforcement bypass, which this skill's severity guide rates `error`. Both keys belong in the highest-precedence managed source, and managed sources do not merge; that placement is not decidable from the files this skill reads, so report the pairing, not the placement |

Model IDs in `modelOverrides` are not validated here: unknown keys are ignored rather than
rejected, and deciding whether a key is a real Anthropic model ID means resolving it against
[Models overview](https://platform.claude.com/docs/en/about-claude/models/overview).
