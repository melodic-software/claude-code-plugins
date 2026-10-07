# Settings Audit Checklist

Validation rules organized by category. Each check has a severity, what to look for, and how to verify.

Every Phase 2 category has a table here. What *governs* a category, the reasoning and the ordering a
table row cannot carry, lives alongside it in
[context/validation-categories.md](../context/validation-categories.md).

## A. Schema & Structure

| Check | Severity | How to verify |
| --- | --- | --- |
| All config files are valid JSON | error | `jq . <file>` exits 0 |
| `$schema` present in settings.json | warning | `jq '."$schema"'` returns URL |
| `$schema` URL is `https://json.schemastore.org/claude-code-settings.json` | warning | Exact string match |
| No `mcpServers` key in settings.json or settings.local.json | error | `jq '.mcpServers // empty'`. MCP defs go in `.mcp.json` |
| settings.local.json does not contain `hooks` (team config, not personal) | info | `jq '.hooks // empty'` |

## B. Permissions

### B.1 / B.2 / B.3 Baseline permission patterns

Iterate the baseline patterns in [required-permissions.md](required-permissions.md); assert presence
per sub-category:

| Sub-category | Target array in `settings.json` | Severity |
| --- | --- | --- |
| `sensitive-file-deny` | `permissions.deny` (Read patterns) | error |
| `destructive-bash-deny` | `permissions.deny` (Bash patterns) | error |
| `ask-rules` | `permissions.ask` (Bash patterns) | warning; info when the team-tracked `.claude/source-control.md` declares an unattended-push lane (narrowing 1) |

The baseline covers the cross-repo security floor (sensitive `.env*` / `secrets/**` /
`settings.local.json`; destructive `git push --force` / `git push -f` / `git reset --hard` /
`git clean` families; ask on `git push`). Projects that document additional required patterns in their
own rules (extra secret-file paths, destructive API-endpoint families, hook-bypass blockers,
additional ask-gates) get those checked at the same severities.

The severities above are the *unnarrowed* rating. Apply
[required-permissions.md](required-permissions.md) "Narrowing the baseline" first: a documented
exemption or a documented project hook convention retires the finding, and a family already blocked by
a **live** `PreToolUse` hook on the tool surface that pattern defends drops to `info` with the residual
named. "Live" is fenced there and is not the same as installed and enabled. Where no hook inventory was
taken, the finding is stated conditionally, not asserted.

### B.4 Syntax checks

| Check | Severity | How to verify |
| --- | --- | --- |
| Deny rules are in settings.json, NOT settings.local.json | error | Bug [#8961](https://github.com/anthropics/claude-code/issues/8961): deny rules in local are silently ignored |
| No blanket `Bash(git *)` in allow (too broad) | warning | Should be split into specific git operations |

### B.5 Completeness

| Check | Severity | How to verify |
| --- | --- | --- |
| `git commit` is in allow list | info | A convenience under auto mode, where the classifier decides the call; never a gap |
| `git fetch` is in allow list | info | Same |
| `git stash` is in allow list | info | Same |

## C. MCP Servers

### C.1 Server command validity

| Check | Severity | How to verify |
| --- | --- | --- |
| stdio server commands resolve on PATH | error | `command -v <cmd>` for each server's command |
| If the repo wraps npx-based MCP servers with a launcher script (Windows cross-platform spawn workaround per CC issue [#36808](https://github.com/anthropics/claude-code/issues/36808)), every npx-based server entry references the same launcher path | error | Check args[0] across npx-using entries. All should point at the same launcher; skip if no launcher convention |
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
| `enableAllProjectMcpServers` is `false` | error | Allowlist pattern: new `.mcp.json` servers must be explicitly approved |
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
| `timeout` is a seconds value, not milliseconds | warning | We read `timeout` as seconds. Flag a **recognizably millisecond-scale** value: a round thousands multiple such as `30000` or `120000`, which read as seconds are 8 h and 33 h. Do NOT flag merely-large values: the reference sets per-type defaults, not a maximum, so a deliberately long-running hook may legitimately run longer than its default. When the value is large but not millisecond-shaped, corroborate against the hook's expected runtime before reporting anything. Pointer: for the unit and the per-type defaults, see [hooks: common fields](https://code.claude.com/docs/en/hooks#common-fields). As of: 2026-10-01. Recheck trigger: that field's unit changes, or the reference adds a maximum |
| Timeouts are reasonable (5-15s for simple formatters, 30s for slow-startup tools such as pwsh) | warning | Compare against known good values. These figures are this skill's judgment, not a documented limit |
| Matcher takes its intended evaluation path | warning | Classify the matcher by its characters, confirm exact-match vs regex matches intent, anchor regex-path matchers with `^…$` |
| Shell-form path placeholders are quoted | warning | Flag a shell-form hook whose project/plugin placeholder is unquoted, in **either** spelling, braced (`${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}`) or bare-dollar (`$CLAUDE_PROJECT_DIR`), since both reach the shell and an unquoted path breaks on a space either way. Do **not** flag shell form itself, and do not flag quoted shell form. For a hook that names a path placeholder, the report may suggest exec form as an option; which form fits a given hook is the pointer's to say, not this row's. Pointer: for the quoting rule, see [hooks: reference scripts by path](https://code.claude.com/docs/en/hooks#reference-scripts-by-path); for when each form fits, see [hooks: exec form and shell form](https://code.claude.com/docs/en/hooks#exec-form-and-shell-form). As of: 2026-10-01. Recheck trigger: either section changes its quoting rule or its form preference |
| Exec-form `command` resolves on every platform the repo targets | error | Flag only for a repo that runs on Windows: an exec-form hook whose `command` is not a real executable that runs the hook there. `bash`, `sh`, a `.sh` path, and a `.cmd`/`.bat` shim are examples, not the whole set. On macOS and Linux the same hook is not a finding. We rate it `error` because a gate hook that does not launch enforces nothing. Do not accept bare `bash` with the script in `args` as the fix. The fixes we accept: `"command": "node"` with the script path in `args`, or shell form with `"shell": "bash"`. For why each of these fails or works on Windows, follow the pointer. Pointer: for the Windows exec-form rule, see [hooks: exec form and shell form](https://code.claude.com/docs/en/hooks#exec-form-and-shell-form). As of: 2026-09-28 (our probe: raw `hooks.md`, 330,813 bytes, SHA-256 `57e3b47d55acfbae3dcdc112866c8c0f75528d8b5c4fca9bfcdaa904d4728218`). Recheck trigger: that section's Windows rule changes, or [anthropics/claude-code#90495](https://github.com/anthropics/claude-code/issues/90495) closes (args dropped, the hook still routed through `bash.exe`). This marketplace's `scripts/check-exec-form-windows-probe.sh` checks its own rows; a non-Windows skip does not clear #90495 |
| No duplicate hooks (same script registered twice for same event) | info | Compare commands within each event |
| Hook events are valid per official docs | error | The engine reads the Event table of the [hooks reference](https://code.claude.com/docs/en/hooks) each run (`hook-event` rows). Read the page yourself only for a `not-inspectable` row, live rather than from a recalled event list |
| Hook-suppression levers are read and reported | info | Read `disableAllHooks` from the settings-declared layer and `allowManagedHooksOnly` / `strictPluginOnlyCustomization` from the managed layer. Report each as set or unset with the hooks it switches off. `info` because the reading is state, not a defect: a repo may set any of them deliberately. It is not optional, though: **B.1–B.3's third narrowing may not downgrade a missing deny rule on the strength of a hook one of these has already disabled**, so an unread lever means the narrowing is unavailable rather than assumed clear |
| Mod-plane keys are read and reported (engine: `D/mod-plane`) | info | The engine reads `prependPlugins`, `appendPlugins` and `disableSideloadFlags` at every scope, and the built-in guard's `allowManagedModsOnly` and `allowModsToOverrideDenyRules` under `pluginConfigs["cc-plugin-sec-default@builtin"].options`. None switches a settings hook off, so none feeds the lever narrowing. A copy in a scope Claude Code does not read for that key is an `info` finding, since it changes nothing. Report `allowModsToOverrideDenyRules: true` beside Category B: a user's mod can then approve a call a `deny` rule refuses. **Claim:** the three top-level keys and their scopes (`prependPlugins`/`appendPlugins`: managed, or user only on a machine with no managed settings for a user not signed in with a Team or Enterprise plan, never project, local or `--settings`; `disableSideloadFlags`: managed, rejecting `--plugin-dir`, `--plugin-url`, `--agents` and `--mcp-config`); the two guard options are read only from managed settings, only under that id, and only where the guard loads; `disableAllHooks` in managed settings stops every installed plugin's mod as well as hooks. **Basis:** [settings-reference](https://code.claude.com/docs/en/settings-reference) `prependPlugins`, `appendPlugins`, `disableSideloadFlags`; [mods admin](https://code.claude.com/docs/en/plugins/mods/admin) "Set options on the built-in guard"; [mods reference](https://code.claude.com/docs/en/plugins/mods/reference) settings table; all fetched as raw markdown 2026-10-01. **As of:** 2026-10-01, Claude Code 2.1.287. **Recheck:** a key's scope bullet or the guard's option table changes, or a release note names one of these keys |

## E. Plugins

| Check | Severity | How to verify |
| --- | --- | --- |
| Every plugin's marketplace exists in `extraKnownMarketplaces` | error | Split `@marketplace` suffix, verify marketplace key exists |
| No enabled plugin depends on a disabled plugin | warning | The engine merges user, project and local `enabledPlugins` and reads each enabled plugin's `.claude-plugin/plugin.json` `dependencies` (direct only). A merged `false` that an enabled plugin declares is `dependency-disabled`; every other `false` is an inventory row. See [validation-categories.md](../context/validation-categories.md) "E.1" |
| Each enabled plugin is listed in its marketplace catalog (`.plugins[].name`) and is not a key of that catalog's `renames` map; a renamed key reports the new name, a `null` entry reports removed | warning | `check-plugin-drift.sh` reads `.renames` from the catalog already in hand. A key mapped to a name is followed to the end of the chain and reported as a rename naming that final name. A `null` entry is a removed row, not an orphan. A key absent from the map stays on the name-similarity heuristic. A chain that repeats a name is reported as a cycle and is not given a final name. See [validation-categories.md](../context/validation-categories.md) "E.2". Pointer: when the map's effect on a settings file is in question, fetch [Migrate users with a renames map](https://code.claude.com/docs/en/plugins/host-marketplace#migrate-users-with-a-renames-map) live. As of: 2026-10-03. Recheck trigger: that section changes what a renames entry points at, how a chain is followed, or which settings files a session rewrites |
| Every enabled plugin has a component definition, and none has two | error | Read the [Strict mode section](https://code.claude.com/docs/en/plugins/marketplace-reference#strict-mode) and the entry rules above it on marketplace-reference; do not restate them from memory. Do not flag a plugin with no `plugin.json` whose marketplace entry declares its components, whatever `strict` says; a bare root `marketplace.json` is not by itself a finding. Error conditions: a plugin with no `plugin.json` and no entry declaring its components (nothing defines what loads), and an entry that declares component fields beside a `plugin.json` under `strict: false`. For what each case does at load, follow the pointer. Pointer: that section's result table and its conflict error, both spans pinned in `doc-citations.tsv`. As of: 2026-09-29. Recheck trigger: `check-doc-citations.sh` fails on either span, or the section's result table changes |

## F. Environment Variables

| Check | Severity | How to verify |
| --- | --- | --- |
| Env vars in settings.json are documented CC vars | warning | Read `code.claude.com/docs/en/env-vars` and search it for each env var name. WebSearch alone is insufficient. **Read it verbatim, not through a summarizer.** The page is long and a summarizing fetch truncates it, then reports the rows past the cutoff as absent: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/fetch-docs.sh" --cache --max-age 0 --out <dir> env-vars` and grep `<dir>/env-vars.md`, per the [fetch route](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/upstream-drift/README.md#reading-the-basis-the-fetch-route). A truncated read supports NO finding. Say so and move on. **Absence from this page is not "unrecognized" either:** it is not the whole env-var surface, and `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_CODE_ENHANCED_TELEMETRY_BETA`, and `CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS` are all real and all absent from it (our probe, a full verbatim read; no artifact stored. Pointer: [env-vars: variables](https://code.claude.com/docs/en/env-vars#variables). As of: 2026-08-10. Recheck trigger: `env-vars` gains a row for any of them). A name missing here is at most "not documented on `env-vars`". Check `monitoring-usage`, `mcp`, and `settings` before writing anything stronger |
| No secrets in settings.json (tokens, keys, passwords) | error | Scan for patterns: `ghp_`, `eyJ`, `sk-`, `AKIA`, common token prefixes. The engine's `SECRET_RE` is a literal list of vendor token shapes, not derived from the docs: neither `settings-reference` nor `env-vars` states any credential format (our probe: a full verbatim read of both found no `ghp_`, `github_pat_`, `eyJ`, `sk-`, `AKIA`, or `xox` shape), and the token shapes belong to GitHub, AWS, Slack and others. Never narrow the literal to match a doc. Pointer: [settings-reference](https://code.claude.com/docs/en/settings-reference), the whole page, since the probe is a negative over every section, and [env-vars: variables](https://code.claude.com/docs/en/env-vars#variables); no artifact stored. As of: 2026-09-29, Claude Code 2.1.284. Recheck trigger: either page documents a credential format; then derive the pattern from it and keep the literal as the fallback |
| Secrets are in settings.local.json only | error | settings.local.json is gitignored |

## G. Skill-listing budget

Unlike every other category here, G's inputs are not in a settings file this skill already opened.
They are the listing the running harness assembled. So the first two rows are about *taking a
measurement at all*, and the rest only apply once one exists.

| Check | Severity | How to verify |
| --- | --- | --- |
| Overflow was measured by a route that works in this run's mode | warning | **Existing log first**: the engine reads a debug log this session already wrote (`--debug-log`, then `CLAUDE_CODE_DEBUG_LOGS_DIR`, then the newest file under `<user dir>/debug/`, the locations the [CLI reference](https://code.claude.com/docs/en/cli-reference) and [env-vars](https://code.claude.com/docs/en/env-vars) document) and parses the over-budget warning from it, skill count, characters and budget included; a log with no warning reads as fitting. Only with no log at all: **Interactive**: `/doctor` reports the listing's cost and its biggest contributors, and needs a TTY, so prompt the user to run it and paste the output. **Headless** (`-p`, spawned agent, background job): re-launch with `--debug` and look for the budget warning Claude Code writes to the debug log ([skills](https://code.claude.com/docs/en/skills), "Skill descriptions are cut short"). `/context`'s Skills row is a second *interactive* reading only. Name the route in the finding |
| No measurement is reported as "not measured", never as "no overflow" | error | An unmeasured category that reports clean is the failure mode this row exists to block, the same defect as a passing check that never ran |
| Any overflow finding names the budget constant it was measured against | warning | `skillListingBudgetFraction` (**default `0.01`**) × context window × ~4 chars/token, or `SLASH_COMMAND_TOOL_CHAR_BUDGET` when set (**documented fallback 8,000 chars**). Confirm both in Phase 3.1 against [settings-reference](https://code.claude.com/docs/en/settings-reference) and [env-vars](https://code.claude.com/docs/en/env-vars), since they are upstream-owned. Without the constant the report cannot say *how far* over |
| Roster composition counted before any lever is recommended | warning | Count listing entries by origin: plugin skills, project skills (`.claude/skills/`), user skills (`${CLAUDE_CONFIG_DIR:-~/.claude}/skills/`). This decides which levers exist |
| Every recommended lever is reachable for the origin it targets | error | We treat `skillOverrides` as reaching project and user skills only, never plugin skills. On a plugin-heavy roster the levers are `/plugin` and upstream description trimming. Recommending `skillOverrides` for a plugin skill is a lever the operator cannot pull. Pointer: [settings-reference: `skillOverrides`](https://code.claude.com/docs/en/settings-reference#skilloverrides), the span pinned in `doc-citations.tsv`. As of: 2026-09-27. Recheck trigger: `check-doc-citations.sh` fails on that span |
| No `skillOverrides` entry targets a plugin skill (engine: `G/skill-override-plugin`) | warning | For each `skillOverrides` key holding `:` in the user, project and local settings files, the engine takes the text before the first `:` and looks it up among the plugin names in the installed registry and every `enabledPlugins` key. A match is inert, since the override does not reach plugin skills (pointer: [skills: override skill visibility from settings](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings); as of: 2026-09-27; recheck trigger: that section changes whether overrides reach plugin skills). The reachable levers are `enabledPlugins` or `/plugin` for the whole plugin, or `disable-model-invocation` in the skill's frontmatter, which is the plugin author's to set. A colon key whose prefix names no plugin is a `skip` row, never clean and never a finding: it may be a nested directory-qualified skill (`apps/web:deploy`) or a claude.ai-synced skill (`anthropic-skills:`), and the docs do not settle whether an override reaches it. A key naming no skill anywhere is not detected: bundled and synced skill names are not enumerable from files |
| `skillOverrides` in the user dir's `settings.local.json` is flagged (engine: `G/skill-override-home-local`) | info | The engine reads `<user dir>/settings.local.json` whatever the project root. We treat that file as the project-local settings file for sessions started in the home directory only, so its entries reach no other project (pointer: the scope table in [settings: settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect), its project-local and user rows; as of: 2026-10-01; recheck trigger: that table changes who a project-local or user settings file reaches). A user-wide override belongs in `settings.json`. The entry may be intended: we treat the `/skills` menu as writing to this file from a home-rooted session (pointer: [skills: override skill visibility from settings](https://code.claude.com/docs/en/skills#override-skill-visibility-from-settings); as of: 2026-10-01; recheck trigger: that section changes which file the menu writes). Present but unreadable or invalid is `not-inspectable` |
| Per-entry text within the per-skill cap | warning | Combined `description` + `when_to_use` ≤ `skillListingMaxDescChars`, which this row keeps at **`1536`** as its own setting. Confirm it in Phase 3.1. This is a per-entry cap, independent of the shared budget above. Pointer: for the default, see the [frontmatter reference](https://code.claude.com/docs/en/skills#frontmatter-reference). As of: 2026-08-31. Recheck trigger: the default moves, which re-derives this row |

### Measuring it in a repository (in-repo proxy, not the real population)

Where the audited target is a repository that *publishes* skills, the `skill-quality` plugin ships the
aggregate measurement as `skill-quality:check`'s `listing-budget` action. Use it when that plugin is
installed, and state plainly what it is and is not:

- **It measures a different population.** The script walks *skills roots in a repository*. Category G
  is asking about *the listing the consumer's running session assembled*, which is the installed
  plugin cache plus that machine's project and user skills. A repository's own roots are a **proxy**
  for that, useful when the audited repo is the publisher, and not a substitute for `/doctor` or
  `--debug` on the consumer's machine. Never present its number as the consumer's listing size.
- **It is slow enough to matter for how you call it.** It scales per skill: one plugin's skills root
  takes seconds, and a marketplace-wide `plugins/*/skills` run takes minutes and exceeds a default
  Bash tool timeout. Scope it to the roots you need, or run it in the background; do not make a
  Category G step depend on a marketplace-wide invocation completing inline.

## H. Model and effort settings

Each check reads a settings file this skill already opens, and each detects a value the harness
accepts into the file and then does not apply the way its author expects. How loudly that surfaces
differs per row, so each row says so rather than the section claiming a blanket silence.

Two of these rows also have an authoring-time path: the declared schema section A checks for
constrains the values of `effortLevel` and `fallbackModel`, so an editor validating against it
flags them before the file is ever loaded. The rows stay for two reasons: the schema is advisory,
so the harness still reads a file that violates it, and section A checks that `$schema` is
present, not what the values are. Where the schema and the harness disagree, the row says which is
which. We rely on the SchemaStore document constraining both keys; for the constraints, read the
document.

- **Pointer**: `https://json.schemastore.org/claude-code-settings.json`, its
  `properties.effortLevel` and `properties.fallbackModel` entries (a JSON document has no section
  anchors, so the entries are named by path).
- **As of**: 2026-09-29
- **Recheck trigger**: either type differs on a fresh fetch.

The engine reads no schema: it never fetches the SchemaStore document, so a limit that only the schema
states (a raw array-length limit on `fallbackModel`) is a `skip` row, not a finding, and the engine
applies no number that a page it read does not state. Fetching the schema would add a second network
dependency whose version can drift from the installed CLI, and the schema's constraints are the
authoring-time path the paragraph above already assigns to an editor.

Apply `jq` recipes to `settings.json` and `~/.claude/settings.json`. For `settings.local.json`,
follow this skill's safe-read rule and go through `check-structure.sh`, which reports these keys by
value: `Effort level`, `Fallback chain` (raw and post-dedup counts), `Fallback entries` in order,
`Available models`, and `Enforce available models`. It distinguishes `unset` from `(empty list)`
because those are different findings. Env and permission entries stay counts there, so a key that
lives only in the local file is still checkable without dumping the secrets beside it. Resolve
current behavior from <https://code.claude.com/docs/en/model-config> when the audit runs, the way
section F resolves environment variables against their own page.

| Check | Severity | How to verify |
| --- | --- | --- |
| `effortLevel` is a value its **Type** bullet documents | warning | `jq '.effortLevel'`. The accepted values are the **Type** bullet of the [`effortLevel` section](https://code.claude.com/docs/en/settings-reference#effortlevel) on settings-reference; the engine reads that bullet each run and reports any other value. Report it as a value the page does not document; the page does not state what runs instead, so do not assert a level |
| `fallbackModel` keeps no more distinct models than the page says the chain keeps | warning | The cap is the number the [`fallbackModel` section](https://code.claude.com/docs/en/settings-reference#fallbackmodel) states for distinct allowed models; the engine reads it each run and applies no other. A section that states none gives one `skip` row. Two tests can disagree: the declared schema caps RAW array length, while the page caps the chain after duplicate removal, so with a cap of 3 `["sonnet","haiku","sonnet","opus"]` has 4 raw entries and exactly 3 distinct. Only the distinct count is a finding; a raw count above the cap is a `skip` row because the schema is not read. Dedupe in place with `jq '.fallbackModel \| reduce .[] as $m ([]; if index($m) then . else . + [$m] end)'`, since `unique` would sort away the order the chain is tried in, and name any entry past the cap as at risk of being ignored. Not "dead": allowlist-excluded entries are also dropped when the chain is read, and the page does not state whether that dropping happens before or after the cap. Pointer: for the cap and the allowlist drop, see the [`fallbackModel` section](https://code.claude.com/docs/en/settings-reference#fallbackmodel) and [model configuration: fallback model chains](https://code.claude.com/docs/en/model-config#fallback-model-chains); for the raw-length limit, the SchemaStore document's `properties.fallbackModel`. As of: 2026-10-01 (both pages state a cap and neither orders the allowlist drop against it). Recheck trigger: either page drops or changes its cap, or states whether the allowlist drop runs before the cap |
| Any other string-valued key whose **Type** bullet lists its values holds one of them | warning | `jq 'to_entries[] \| select(.value \| type == "string")'` over `settings.json` and `~/.claude/settings.json`; `settings.local.json` is not read by value. The engine takes the values from the `string, one of:` bullets on settings-reference, treats an entry such as `custom:<slug>` as matching any text in its placeholder, and gives a key with no such list no row. A list holding a bullet that is not a literal value, such as the strftime pattern in the `timeFormat` list, is open: its literals are not the whole set, so the key has no row. `effortLevel` and `disableDeepLinkRegistration` keep their own rows. A key whose Type bullet states its values inline in a sentence is not parsed, so it has no row |
| `availableModels` does not mix a family wildcard with a specific entry of that family | warning | The engine fixes the families as `opus`, `sonnet`, `haiku` and `fable`; the record below the table says why. Flag a list that holds a family's wildcard and also an entry naming a specific model of that family; we read the pair as narrower than its author meant. A Mantle ID, or an `ANTHROPIC_CUSTOM_MODEL_OPTION` value embedding a family name, counts as such an entry. This row is not silent at run time (the pointer says how Claude Code tells the user), so the finding is the narrowing itself. For what the list then permits, follow the pointer. Report the models they most likely still expect to be selectable. Pointer: [model configuration: merge behavior](https://code.claude.com/docs/en/model-config#merge-behavior). As of: 2026-10-01. Recheck trigger: that section changes how a specific entry interacts with its family's wildcard |
| `enforceAvailableModels: true` is paired with a non-empty `availableModels` | error | `jq 'select(.enforceAvailableModels == true) \| .availableModels'`. The finding requires the flag to be `true` AND the list unset or empty. An explicit `false` is someone turning enforcement off on purpose and is never a finding, so gate on the value rather than the key's presence. When it does fire: we treat the key as having no effect without a non-empty `availableModels`, so the constraint its author set is not in force. That is an enforcement bypass, which this skill's severity guide rates `error`. Where both keys must live is a managed-settings placement question this skill cannot decide from the files it reads, so report the pairing, not the placement. Pointer: [settings-reference: `enforceAvailableModels`](https://code.claude.com/docs/en/settings-reference#enforceavailablemodels). As of: 2026-10-01. Recheck trigger: that section changes what the key does with an empty or unset list |

The engine keeps the family list fixed because no page it reads gives a list to parse: our probe of
the model-config page found no table or list that marks which aliases name a family (no artifact
stored).

- **Pointer**: for the aliases, see
  [model configuration: model aliases](https://code.claude.com/docs/en/model-config#model-aliases).
- **As of**: 2026-09-30, Claude Code 2.1.285
- **Recheck trigger**: that table gains a marker for family aliases, the page states the family
  aliases as a list, or the engine starts reading the page.

Model IDs in `modelOverrides` are not validated here: unknown keys are ignored rather than
rejected, and deciding whether a key is a real Anthropic model ID means resolving it against
[Models overview](https://platform.claude.com/docs/en/about-claude/models/overview).

### `bashOutputMaxChars`

We treat `bashOutputMaxChars` as a context-cost dial: a set value is the operator's choice, and we
never recommend raising it, because inline command output is context the session pays for. We
treat `taskOutputMaxChars` as dead on Claude Code v2.1.277 and later, our setting for this row.

- **Pointer**: for the key's range, default and minimum version, see
  [settings-reference: `bashOutputMaxChars`](https://code.claude.com/docs/en/settings-reference#bashoutputmaxchars),
  and the `taskOutputMaxChars` note on the same page.
- **As of**: 2026-09-28
- **Recheck trigger**: that page changes the range or the default, or restores
  `taskOutputMaxChars`.

| Check | Severity | How to verify |
| --- | --- | --- |
| `bashOutputMaxChars` is unset, or an integer in the page's range | info | `jq '.bashOutputMaxChars'`. Report a set value as a context-cost choice, not as a defect. Do not recommend raising it. Report `taskOutputMaxChars` as dead on Claude Code v2.1.277 and later |

### `effort:` and `model:` frontmatter on skills and agents

The rows above read settings files. A durable effort or model choice also lives in component
frontmatter, `effort:` and `model:` on a skill or subagent definition, and that placement is
**this section's**, by an explicit hand-off rather than by inference: the instruction-audit
catalog's effort row states "**Must NOT flag:** `effort:` frontmatter and `effortLevel` settings
keys as such … a config-mechanics finding belonging to `harness-config:audit`"
([`../../audit-instructions/reference/criteria.md`](../../audit-instructions/reference/criteria.md),
row I21). Without a row here, a component pinning a level is reached by neither skill. Each
pointing at the other is the shape a hand-off takes when nobody closes it.

| Check | Severity | How to verify |
| --- | --- | --- |
| A component's `effort:` pin names the model it was calibrated against, or an event that re-opens it | info | Read the frontmatter of every `skills/*/SKILL.md` and `agents/*.md` in scope. We treat a pin as calibrated to the model it was set on, so a pin that names neither that model nor an event that re-opens it is flagged. **Do not flag a pin at the resolved model's own default level.** That pin encodes no measurement that could go stale. The default levels this row applies, our setting when no fetch is possible: `medium` on Opus 5.5 and Sonnet 5.5, `xhigh` on Opus 4.7, `high` on every other model with effort support. Confirm them against the pointer when the audit runs. Report the missing re-derivation, never the level itself; whether the level is high enough is the next row's question, not this one's. Pointer: for where each model's default is set, see [model configuration: adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level); for per-model calibration, see [choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level). As of: 2026-10-01. Recheck trigger: a model's default on that page differs from this row's setting |
| A code-changing or verifying component's `effort:` is not pinned below `medium` | warning | Read the same frontmatter. Flag an agent or skill whose `effort:` is pinned below `medium` (today that is `low`) when its body has the model change code (edit, implement, refactor, fix) or verify a change (run the build, the tests, a review, or a check that a change works). The floor is the marketplace's [Effort floor](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/plugin-philosophy.md#effort-floor): `medium` or above for that work on every model that supports effort. Classify by what the body has the model do, not by its name or tool grants. **Do not flag:** a component with no `effort:` pin, which inherits the session level and is not a pin; a read-only, chat-like, or mechanical component (lookups, formatting, listing) pinned `low`; or a model the pin runs on that has no effort support, where the key has no effect. Propose `medium` as the floor and leave any higher level to the author. Pointer: the floor's own record in that section, which points at the upstream effort pages. As of: 2026-10-01. Recheck trigger: that section changes the floor level or the kinds of work it covers |
| No effort pin rests on a model-config effort table or default that changed since the baseline | warning | Run `bash "<skill-dir>/scripts/check-effort-pins.sh" [--root <dir>] [--baseline <file>] [--docs-dir <dir>]` and report its lines verbatim; `--print-baseline` prints a new baseline line and writes nothing. Exit 0: the page matches [`effort-table.baseline`](effort-table.baseline) and every pin names a listed level. Exit 1: the page changed (`reason=table-changed` on every pin) or a pin names an unlisted level (`reason=level-not-in-table`); a person re-decides each flagged pin. Exit 3: page unread or reshaped, no claim about any pin. Exit 2: fatal. The script never edits a pin or the baseline; the rebaseline step is in [SKILL.md](../SKILL.md) |
| A component's `effort:` and `model:` are consistent with each other | info | A definition setting `model:` without `effort:` inherits the session's level, and the two together are what a spawn actually runs on. Flag only the combination the author is unlikely to have intended: a cheap `model:` tier paired with a top effort level, or the reverse, with no stated reason. Report the mismatch, never a preferred pairing |

These rows read a set `effort:` as the level the component runs at and an absent one as the
session level. A level the frontmatter field accepts is not evidence that the `effortLevel`
settings key accepts it; check each against its own pointer.

- **Pointer**: for the field's precedence and accepted levels, see the
  [subagents frontmatter fields](https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields);
  for the settings key, see
  [settings-reference: `effortLevel`](https://code.claude.com/docs/en/settings-reference#effortlevel).
- **As of**: 2026-10-01 (both pages read as raw markdown)
- **Recheck trigger**: the field's precedence or either accepted-level list changing.

## I. Deep-link registration

These rows read the setting that governs whether Claude Code registers the `claude-cli://`
handler, never the places the handler is registered: whether it is in fact registered on a given
machine is workstation state, not configuration. For when and where Claude Code registers it,
follow the pointer.

- **Pointer**: for when registration happens and where it writes, see
  [deep links: registration and supported platforms](https://code.claude.com/docs/en/deep-links#registration-and-supported-platforms).
- **As of**: 2026-09-29
- **Recheck trigger**: that section changes when registration happens or where it writes.

Like two of section H's rows, the value check has an authoring-time path: the declared schema
constrains this key's value, so an editor validating against it flags a boolean before the file is
ever loaded. The row stays for the same reasons those do: the schema is advisory, the harness still
reads a file that violates it, and section A checks that `$schema` is present, not what the values
are. The SchemaStore document and the deep-links page (linked above) disagree on when registration
happens.

- **Pointer**: `https://json.schemastore.org/claude-code-settings.json`, its
  `properties.disableDeepLinkRegistration` entry (a JSON document has no section anchors, so the
  entry is named by path), and the deep-links section linked above.
- **As of**: 2026-09-29
- **Recheck trigger**: the key's type or the registration wording differs on a fresh fetch.

**Reach.** Read the key by value from `.claude/settings.json` and `~/.claude/settings.json`.
`check-structure.sh` does not report it, so a `settings.local.json` or managed-settings occurrence
is outside what this skill's safe-read rule surfaces. Record it as not inspectable rather than
reporting the key as absent. The managed gap is not one a file read would close: server-managed
delivery, an MDM plist, and Windows registry policy are all managed sources with no file in the path
this skill resolves, and which of them wins for this key is the managed-settings page's to say
(pointer: [managed settings: precedence within the managed
tier](https://code.claude.com/docs/en/managed-settings#precedence-within-the-managed-tier); as of:
2026-10-01; recheck trigger: that section moves or changes which managed source wins).
Nothing about the managed layer is decidable here, present or absent. Both rows below are built only on what the readable scopes show.

| Check | Severity | How to verify |
| --- | --- | --- |
| `disableDeepLinkRegistration`, **when present**, is a value its **Type** bullet documents | warning | `jq 'select(has("disableDeepLinkRegistration")) \| .disableDeepLinkRegistration'`. Gate on `has(…)`, never on the value being non-`null`: a bare `jq '.disableDeepLinkRegistration'` returns `null` for an absent key and for an explicit `null` alike, and an absent key is a consumer accepting the default registration on purpose, never a finding. The check fires only on a key that is present and not a documented value. The accepted value is the **Type** bullet of the [`disableDeepLinkRegistration` section](https://code.claude.com/docs/en/settings-reference#disabledeeplinkregistration) on settings-reference; the engine reads that bullet each run. Boolean `true` is the likely author error, the key reading as a flag; the declared schema (record above) flags it too, so a schema-aware editor catches it first. Report that the documented prevention is not invoked, so nothing exempts the machine from the default registration the section pointer above covers. Do **not** assert what the harness does with an unrecognized value, or that anything surfaces when it reads one, since neither page states either. Pointer: that settings-reference section and the deep-links section linked above, read whole for this negative. As of: 2026-10-01. Recheck trigger: either page states what Claude Code does with a value other than the documented one |
| Where enforcement is required, a `disableDeepLinkRegistration` already set to `"disable"` is not left sitting in a scope that cannot enforce it | warning | We treat `"disable"` in any `settings.json` as preventing registration on that machine, and only a managed-settings entry as enforcing it across an organization (pointer: [deep links: registration and supported platforms](https://code.claude.com/docs/en/deep-links#registration-and-supported-platforms); as of: 2026-09-29; recheck trigger: that section changes where the key enforces). Only managed settings enforce, so no scope this audit reads by value can satisfy such a requirement. Both halves of the gate are therefore observable: the finding requires a declared enforcement requirement (the consuming repo's own rules, or the run's stated policy context) AND the key present with `"disable"` in `.claude/settings.json` or `~/.claude/settings.json`, a visible attempt lodged in a scope that cannot deliver it. We treat a user-scope entry as overridable by project and local scope as well as unenforcing (pointer: [settings: settings precedence](https://code.claude.com/docs/en/settings#settings-precedence); as of: 2026-10-01; recheck trigger: that section moves user scope above project or local). Report **the visible placement**, never the system: say that this entry does not enforce the requirement and that whether a managed source separately carries the key is outside this audit's reach, since server-managed delivery, MDM plist, and registry policy have no file on the path it resolves. Route the administrator to `/status`, the one documented way to see which managed source is active (pointer: [server-managed settings: settings precedence](https://code.claude.com/docs/en/server-managed-settings#settings-precedence); as of: 2026-10-01; recheck trigger: that section names a different command for seeing the active managed source). Deliberately `warning`, not the `error` its `enforceAvailableModels` sibling carries: a bypass is precisely what cannot be proven from here, and managed settings may already enforce this correctly. It becomes `error` only once an administrator confirms no managed source carries the key. Two cases that are **not** findings by design: the key absent from every readable scope (nothing visible to report on), and someone setting it in their own `~/.claude/settings.json` with no enforcement requirement in play, which is the documented single-machine usage. The two rows are sequential, not simultaneous: a key that is present but wrongly valued fails this row's `"disable"` clause and draws only the row above, and correcting the value in that same scope is what brings it into this gate. So say so when both conditions are in view, rather than reporting a placement finding the gate does not yet support |

## J. Known-issues fix versions

Each check compares a fix version a [known-issues.md](known-issues.md) row records with the Claude
Code version the engine read from `claude --version`. The form a row records it in is that file's
"Recording a fix version".

| Check | Severity | How to verify |
| --- | --- | --- |
| An issue whose row records `Fixed in vX.Y.Z` is not kept as a workaround the installed version already outgrew | info | The engine's `known-issue-fixed` rows: `finding` when the installed version is at or past the fix version, `ok` when it predates it, `skip` when the installed version was unreadable. Confirm the issue's live state in Phase 3.2 before recommending the workaround's retirement |
