# external-agents

A Claude Code plugin that hands tasks and reviews to other vendors' official coding-agent CLIs
through their documented headless surfaces. Codex is the first CLI. Each CLI gets one skill; one
shared runner is the only code that calls a CLI.

It replaces OpenAI's `codex@openai-codex` plugin
([openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc), read as the upstream source;
none of its text or code is copied).

## Status

In progress: `run`, `review`, `status`, `result`, `cancel`, `update` and `models` work, and
`/external-agents:codex` and `/external-agents:antigravity` drive them.

## Surface

- **`external-agents`**, on the Bash `PATH` while the plugin is enabled: `run`, `review`, `status`,
  `result`, `cancel`, `update` and `models`. `review:council` calls `external-agents review <product>`
  and `/multi-agent:route` calls `external-agents models <product>`; nothing outside this plugin
  reads its install path, its scripts or its cache files.
- **`/external-agents:codex`**: hands a task, an investigation or a review to Codex
  as a background job, and reads back, resumes or cancels its jobs.
- **`/external-agents:antigravity`**: the same for Google's Antigravity CLI (`agy`). agy runs
  read-only unless you opt in to writes with `antigravity.uses.task.mode: write`, because agy's
  write mode has no network isolation.
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
| `models` | Each model as the CLI lists it: `id` (the value `--model` takes), `name` when the CLI gives one, and, when the CLI reports them per model, `efforts` and `default_effort`. |
| `models_source` | The command the list came from. |
| `efforts`, `efforts_source` | The effort levels the CLI's help lists for its effort flag, and that help command; absent when the CLI reports effort per model instead. A help whose effort line lists no choices this plugin can read makes the result `failed`, never `ok` without levels. |
| `docs_index` | The vendor's docs index, for facts no command reports. |

The plugin ships no model names: every value comes from the installed CLI. The output of each
command is cached per CLI version beside the help `update` captures, so a second call asks the CLI
only for its version.

- **agy**: `agy models` gives the models; agy's `--help` gives the `--effort` levels. agy's model
  ids can carry an effort word of their own (`<model>-high`); both are reported as agy prints them.
- **Codex**: `codex debug models` gives the catalog, each model with its own effort levels and
  default. It is a debugging subcommand the Codex docs do not describe, so a Codex release can
  change it; `external-agents update codex` runs it every time and reports `check: cli facts` when
  it fails. Models the catalog marks hidden are left out.

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
