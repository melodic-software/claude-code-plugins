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

The severities above are the *unnarrowed* rating. Apply
[required-permissions.md](required-permissions.md) "Narrowing the baseline" first: a documented
exemption or a documented project hook convention retires the finding, and a family already blocked by
an installed, enabled `PreToolUse` hook drops to `info` with the residual named. Where no hook
inventory was taken, the finding is stated conditionally, not asserted.

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
| `timeout` is a seconds value, not milliseconds | warning | The [hooks reference](https://code.claude.com/docs/en/hooks) states for `timeout`: "Seconds before canceling. Defaults: 600 for `command`, `http`, and `mcp_tool`; 30 for `prompt`; 60 for `agent`." Flag a **recognizably millisecond-scale** value — a round thousands multiple such as `30000` or `120000`, which read as seconds are 8 h and 33 h. Do NOT flag merely-large values: the page documents defaults, not a maximum, so a deliberately long-running hook may legitimately exceed 600. When the value is large but not millisecond-shaped, corroborate against the hook's expected runtime before reporting anything |
| Timeouts are reasonable (5-30s for formatters, up to 60s for heavy tools) | warning | Compare against known good values |
| Matcher takes its intended evaluation path | warning | Classify the matcher by its characters, confirm exact-match vs regex matches intent, anchor regex-path matchers with `^…$` |
| Shell-form path placeholders are quoted | warning | Same page: "Prefer exec form for any hook that references a path placeholder. In shell form, wrap each placeholder in double quotes." Flag a shell-form hook whose project/plugin placeholder is unquoted, in **either** spelling — braced (`${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`) or bare-dollar (`$CLAUDE_PROJECT_DIR`), since both reach the shell and an unquoted path breaks on a space either way. Report exec form as the page's preference, but do **not** flag shell form itself — the page endorses omitting `args` when the hook needs pipes, `&&`, redirects, or a `.cmd`/`.bat` shim, and quoted shell form is a documented, correct spelling |
| Exec-form `command` resolves on every platform the repo targets | error | Same page: "On Windows, exec form requires `command` to resolve to a real executable such as a `.exe`." Windows-only constraint — `bash` and `sh` are real executables on macOS/Linux, so flag only for a repo that runs on Windows. There `bash` resolves to the WSL relay `System32\bash.exe` and the launch fails; a failed launch is a non-blocking error, so a gate hook silently enforces nothing. Fixes per the page: a real binary plus the script path in `args` (`"command": "node"`), or shell form with `"shell": "bash"`, which Claude Code routes through Git Bash instead of a PATH lookup |
| No duplicate hooks (same script registered twice for same event) | info | Compare commands within each event |
| Hook events are valid per official docs | error | Cross-reference against the [hooks reference](https://code.claude.com/docs/en/hooks) — fetch it live rather than trusting a recalled event list |

## E. Plugins

| Check | Severity | How to verify |
| --- | --- | --- |
| Every plugin's marketplace exists in `extraKnownMarketplaces` | error | Split `@marketplace` suffix, verify marketplace key exists |
| Explicitly disabled plugins are intentional | info | Review false entries — are they stale or deliberately off? |
| Every enabled plugin has a component definition (`plugin.json` **or** a `strict: false` entry) | error | Test `strict`, not `plugin.json` presence. The [Strict mode section](https://code.claude.com/docs/en/plugin-marketplaces#strict-mode) documents a plugin with no `plugin.json` as SUPPORTED: under `strict: false` "the marketplace entry is the entire definition" — the plugin repo provides raw files and the entry's `skills`/`agents`/`hooks` fields expose them. Anthropic's own `anthropic-agent-skills` marketplace ships three such plugins with zero `plugin.json` files repo-wide, so a bare root `marketplace.json` is **not** by itself a finding. Two error conditions: (1) a plugin with NEITHER — no per-plugin `plugin.json` AND no `strict: false` entry declaring its components — since nothing then defines what loads; (2) a plugin with BOTH — a `strict: false` entry AND a `plugin.json` that declares components — since the same page states "If the plugin also has a `plugin.json` that declares components, that's a conflict and the plugin fails to load" |

## F. Environment Variables

| Check | Severity | How to verify |
| --- | --- | --- |
| Env vars in settings.json are documented CC vars | warning | **MANDATORY**: read `code.claude.com/docs/en/env-vars` and search it for each env var name. WebSearch alone is insufficient. **Read it verbatim, not through a summarizer** — the page is long (315 variable rows on 2026-08-10) and a summarizing fetch truncates it, then reports the rows past the cutoff as absent: `curl https://code.claude.com/docs/en/env-vars.md` to a file and grep the file, per the [fetch route](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/upstream-drift/README.md#reading-the-basis--the-fetch-route). A truncated read supports NO finding — say so and move on. **Absence from this page is not "unrecognized" either:** it is not the whole env-var surface, and `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA`, and `CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS` are all real and all absent from it (verified 2026-08-10 on a full verbatim read). A name missing here is at most "not documented on `env-vars`" — check `monitoring-usage`, `mcp`, and `settings` before writing anything stronger |
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

### `effort:` and `model:` frontmatter on skills and agents

The rows above read settings files. A durable effort or model choice also lives in component
frontmatter — `effort:` and `model:` on a skill or subagent definition — and that placement is
**this section's**, by an explicit hand-off rather than by inference: the instruction-audit
catalog's effort row states "**Must NOT flag:** `effort:` frontmatter and `effortLevel` settings
keys as such … a config-mechanics finding belonging to `claude-config:audit`"
([`../../audit-instructions/reference/criteria.md`](../../audit-instructions/reference/criteria.md),
row I21). Without a row here, a component pinning a level is reached by neither skill — each
pointing at the other is the shape a seam takes when nobody closes it.

| Check | Severity | How to verify |
| --- | --- | --- |
| A component's `effort:` pin names the model it was calibrated against, or an event that re-opens it | info | Read the frontmatter of every `skills/*/SKILL.md` and `agents/*.md` in scope. The effort scale is calibrated **per model**, so the same level name does not carry the same underlying value across models, and a level measured against one model and carried to the next is a pin nobody re-measured — the property is stated unqualified at <https://code.claude.com/docs/en/model-config>, so it holds for every model rather than being a per-model quirk. **Do not flag a pin at the resolved model's own default level** — that pin encodes no measurement that could go stale. Resolve the default from the same page when the audit runs rather than assuming it: as of 2026-08-08 it is `high` everywhere effort is supported except Opus 4.7, which defaults to `xhigh`. **Recheck trigger:** `high` ceasing to be the general default, or the exception set changing. Report the missing re-derivation, never the level itself — which level is right is the author's call and this check has no opinion on it |
| A component's `effort:` and `model:` are consistent with each other | info | A definition setting `model:` without `effort:` inherits the session's level, and the two together are what a spawn actually runs on. Flag only the combination the author is unlikely to have intended: a cheap `model:` tier paired with a top effort level, or the reverse, with no stated reason. Report the mismatch, never a preferred pairing |

**Claim:** a subagent definition's own `effort` overrides the session level rather than yielding to
it, so the frontmatter value is what ships. **Basis:** the [subagents
reference](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields) — "Effort level
when this subagent is active. Overrides the session effort level. Default: inherits from session."
The same row admits `max`, which the `effortLevel` settings key does not, so a level valid here is
not evidence it is valid in a settings file. **As of:** 2026-08-08, fetched as raw markdown.
**Recheck trigger:** that field's precedence or its accepted-level list changing on the page.

## I. Deep-link registration

Claude Code "registers the `claude-cli://` handler with your operating system on macOS, Linux, and
Windows when you send your first prompt of an interactive session" — not at install, and
"starting `claude` and exiting without sending a prompt doesn't register the handler"
([deep links](https://code.claude.com/docs/en/deep-links)). Registration "writes to user-level
locations only" (`~/Applications/Claude Code URL Handler.app`, a
`claude-code-url-handler.desktop` under `$XDG_DATA_HOME/applications`,
`HKEY_CURRENT_USER\Software\Classes\claude-cli`). Whether the handler is in fact registered on a
given machine is workstation state, not configuration: these rows read the setting that governs
registration, never those locations.

Like two of section H's rows, the value check has an authoring-time path: the declared schema
types this key `"type": "string", "enum": ["disable"]`, so an editor validating
against it flags a boolean before the file is ever loaded. The row stays for the same reasons those
do — the schema is advisory, the harness still reads a file that violates it, and section A checks
that `$schema` is present, not what the values are.

**Reach.** Read the key by value from `.claude/settings.json` and `~/.claude/settings.json`.
`check-structure.sh` does not report it, so a `settings.local.json` or managed-settings occurrence
is outside what this skill's safe-read rule surfaces — record it as not inspectable rather than
reporting the key as absent. The managed gap is not one a file read would close: server-managed
delivery, an MDM plist, and Windows registry policy are all managed sources with no file in the path
this skill resolves, and the first non-empty source wins for a key like this one, which is on none of
the page's per-key exception lists. Nothing about the managed layer is decidable here, present or
absent. Both rows below are built only on what the readable scopes show.

| Check | Severity | How to verify |
| --- | --- | --- |
| `disableDeepLinkRegistration`, **when present**, is the string `"disable"` | warning | `jq 'select(has("disableDeepLinkRegistration")) \| .disableDeepLinkRegistration'`. Gate on `has(…)`, never on the value being non-`null`: a bare `jq '.disableDeepLinkRegistration'` returns `null` for an absent key and for an explicit `null` alike, and an absent key is a consumer accepting the default registration on purpose — never a finding. The check fires only on a key that is present and not the string `"disable"`. **MANDATORY**: confirm the accepted value against a live fetch of [settings](https://code.claude.com/docs/en/settings) rather than this row's wording — it is upstream-owned and moves with the harness. The page documents exactly one value that produces the effect: "Set to `"disable"` to prevent Claude Code from registering the `claude-cli://` protocol handler", with `"disable"` as its only example. Boolean `true` is the likely author error, the key reading as a flag; the declared schema's `enum` and `type` already flag it too, so a schema-aware editor catches it first. Report that the documented prevention is not invoked, so nothing exempts the machine from the default first-prompt registration above. Do **not** assert what the harness does with an unrecognized value, or that anything surfaces when it reads one — neither page states either |
| Where enforcement is required, a `disableDeepLinkRegistration` already set to `"disable"` is not left sitting in a scope that cannot enforce it | warning | The deep-links page: "To prevent registration entirely, set `disableDeepLinkRegistration` to `"disable"` in `settings.json`. To enforce this across an organization so users cannot re-enable it, set it in [managed settings](https://code.claude.com/docs/en/server-managed-settings) instead." Only managed settings enforce, so no scope this audit reads by value can satisfy such a requirement. Both halves of the gate are therefore observable: the finding requires a declared enforcement requirement (the consuming repo's own rules, or the run's stated policy context) AND the key present with `"disable"` in `.claude/settings.json` or `~/.claude/settings.json` — a visible attempt lodged in a scope that cannot deliver it. User scope is the settings page's lowest layer, below project and local, so that entry is overridable as well as unenforcing. Report **the visible placement**, never the system: say that this entry does not enforce the requirement and that whether a managed source separately carries the key is outside this audit's reach, since server-managed delivery, MDM plist, and registry policy have no file on the path it resolves. Route the administrator to the one documented check — "Run `/status` to see which managed source is active" ([server-managed settings](https://code.claude.com/docs/en/server-managed-settings)). Deliberately `warning`, not the `error` its `enforceAvailableModels` sibling carries: a bypass is precisely what cannot be proven from here, and managed settings may already enforce this correctly. It becomes `error` only once an administrator confirms no managed source carries the key. Two cases that are **not** findings by design: the key absent from every readable scope (nothing visible to report on), and someone setting it in their own `~/.claude/settings.json` with no enforcement requirement in play, which is the documented single-machine usage. The two rows are sequential, not simultaneous: a key that is present but wrongly valued fails this row's `"disable"` clause and draws only the row above, and correcting the value in that same scope is what brings it into this gate — so say so when both conditions are in view, rather than reporting a placement finding the gate does not yet support |
