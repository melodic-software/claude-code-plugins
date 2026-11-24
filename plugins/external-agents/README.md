# external-agents

A Claude Code plugin that hands tasks and reviews to other vendors' official coding-agent CLIs
through their documented headless surfaces. Codex is the first CLI. Each CLI gets one skill; one
shared runner is the only code that calls a CLI.

It replaces OpenAI's `codex@openai-codex` plugin
([openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc), read as the upstream source;
none of its text or code is copied).

## Status

In progress: `run`, `review`, `status`, `result`, `cancel`, `update`, `models` and `usage` work, and
`/external-agents:codex` and `/external-agents:antigravity` drive them.

## Surface

- **`external-agents`**, on the Bash `PATH` while the plugin is enabled: `run`, `review`, `status`,
  `result`, `cancel`, `update`, `models` and `usage`. `review:council` calls
  `external-agents review <product>` and `/multi-agent:route` calls `external-agents models <product>`
  and `external-agents usage <product>`; nothing outside this plugin reads its install path, its
  scripts or its cache files.
- **`/external-agents:codex`**: hands a task, an investigation or a review to Codex
  as a background job, and reads back, resumes or cancels its jobs.
- **`/external-agents:antigravity`**: the same for Google's Antigravity CLI (`agy`). agy runs
  read-only unless you opt in to writes with `antigravity.uses.task.mode: write`. A write run is
  fenced by agy's terminal sandbox (`--mode accept-edits`); `--unsandboxed auto` opts one run into
  agy's auto mode instead.
- **Extra writable directories:** a write run of either CLI takes a repeatable
  `--add-dir <absolute dir>`; without it the run writes only inside its workspace.
- No hooks, no agents and no `commands/` folder: nothing runs until you or a council run asks.

claude.ai organization plugin sync skips this plugin, because it ships a top-level `bin/`
([org sync](https://claude.com/docs/plugins/org-sync)). It needs a local CLI, so it cannot run there
anyway.

## The models command

`external-agents models <product>` prints one JSON document about the installed CLI and starts no
model turn. It is a public interface: other plugins read it, never this plugin's cache files, and
any change a consumer could notice bumps `schema`.

| Field | Meaning |
|---|---|
| `schema` | Output version, `1` today. |
| `product` | The product asked about. |
| `status` | `ok`; else `unavailable` (exit 4, for example the CLI is missing), `refused` (exit 2, for example an unknown product) or `failed` (exit 1), with a `reason` and no other field. |
| `cli` | `name` and `version` of the installed binary. |
| `unset_model` | What runs when no model is passed: `cli-default` means the CLI's own default. |
| `models` | Each model as the CLI lists it: `id` (the value `--model` takes), `name` when the CLI gives one, optional `context_window` when the CLI reports it, and, when the CLI reports them per model, `efforts` and `default_effort`. |
| `models_source` | The command the list came from. |
| `efforts`, `efforts_source` | The effort levels the CLI's help lists for its effort flag, and that help command; absent when the CLI reports effort per model instead. A help whose effort line lists no choices this plugin can read makes the result `failed`, never `ok` without levels. |
| `tools` | List of tool names the harness offers (from the provider record when the CLI does not list them itself). |
| `image` | Boolean: whether the harness can generate images headless. |
| `breaker` | `{ open, reason, reset_at }` read from the product's breaker file (`open: false` and `null` fields when closed or absent). |
| `docs_index` | The vendor's docs index, for facts no command reports. |

The plugin ships no model names: every value comes from the installed CLI. The output of each
command is cached per CLI version beside the help `update` captures, so a second call asks the CLI
only for its version.

- **agy**: `agy models` gives the models; agy's `--help` gives the `--effort` levels. agy's model
  ids can carry an effort word of their own (`<model>-high`); both are reported as agy prints them.
  Delegated agy runs keep `--disable-slash-commands` (so `/swarm` and `/teamwork` stay unoffered)
  while agy's print-mode subagent tools remain available.
- **Codex**: `codex debug models` gives the catalog, each model with its own effort levels,
  default and optional `context_window`. It is a debugging subcommand the Codex docs do not
  describe, so a Codex release can change it; `external-agents update codex` runs it every time and
  reports `check: cli facts` when it fails. Models the catalog marks hidden are left out.

## The usage command

`external-agents usage <product>` prints one JSON object reporting current plan usage remaining,
running one call outside delegated runs and never printing account ids, emails or plan names. Exit
`0` when `status` is `ok`, `4` when `unavailable` (missing CLI, timeout, exit code 2 or unparsable
output), and `2` for an unknown product.

| Field | Meaning |
|---|---|
| `status` | `ok` or `unavailable`. |
| `remaining` | Remaining plan quota as a fraction from `0` to `1` (absent when `unavailable`). |
| `window` | Window label for `remaining` (for example `5h`, `Five Hour` or `Weekly`), when reported. |
| `resets_at` | ISO-8601 reset timestamp for `remaining`, when reported. |
| `windows` | All parsed window entries (`group`, `window`, `remaining`, optional `resets_at`) when the CLI reports multiple windows. |
| `source` | The command and method the reading came from. |
| `reason` | Present when `status` is `unavailable`. |

- **Codex**: queries `codex app-server` over stdio (`account/rateLimits/read`), reads
  `result.rateLimits.primary` and `secondary`, and reports the one with less left (`usedPercent`
  as a remaining fraction, `resetsAt` epoch seconds as ISO-8601). With both present, `windows`
  lists each with `group` `primary` or `secondary`.
- **agy**: runs `agy --output-format json -p=/usage` directly without `--disable-slash-commands`,
  parses the tab-delimited lines in `response`, reports the lowest remaining fraction with its
  window and reset, and keeps every parsed line in `windows`.

## Requirements

- `node`.
- Each CLI you want to reach, installed and logged in. The plugin never installs one.

## Configuration

`<home>/external-agents.yaml` (team, tracked) and `<home>/external-agents.local.yaml` (personal,
gitignored), `<home>` being the repository's convention home, by default `docs/conventions`. Keys
are in [`schemas/external-agents.schema.json`](schemas/external-agents.schema.json); layers and
precedence are in the
[config-cascade contract](../../docs/contracts/config-cascade/README.md). An unset model, effort or
profile leaves the CLI's own configuration in charge.

One key also has a per-user setting, the plugin's `userConfig` option `antigravity_uses_task_mode`
(`read-only` by default, or `write`), which sets `antigravity.uses.task.mode` in every repository
and worktree for that user. Set it in `pluginConfigs` in your user
`settings.json`:

```json
{
  "pluginConfigs": {
    "external-agents@melodic-software": {
      "options": { "antigravity_uses_task_mode": "write" }
    }
  }
}
```

The command reads it from your user and managed settings itself, since a command run through the
Bash tool gets no `CLAUDE_PLUGIN_OPTION_*` variables. A repository's team or personal file still
wins over it. The option's `options` picker needs Claude Code v2.1.271 or later; an earlier release
cannot load the plugin.

## Job files

Job files, logs, the breaker state and the CLI-facts cache (`cli-facts/<product>/<version>/`, the
CLI's own help captured by `update`) live in the plugin's data directory. An installed copy works
the directory out from its own install path, using the directory name the
[plugin reference](https://code.claude.com/docs/en/plugins-reference#environment-variables)
documents, because a command run through the Bash tool can carry another plugin's
`CLAUDE_PLUGIN_DATA`. A copy that is not installed, such as a checkout, needs `CLAUDE_PLUGIN_DATA`
set to a directory whose name starts with `external-agents-`; any other value is not used.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install external-agents@melodic-software
```

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `antigravity_uses_task_mode` | string | `"read-only"` | read-only (default): /external-agents:antigravity task runs cannot edit files. write: task runs may write, fenced by agy's terminal sandbox, in every repository. A repository's docs/conventions/external-agents.yaml or .local.yaml antigravity.uses.task.mode wins over this option. |

### How to set these

Set the options above for `external-agents@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->
