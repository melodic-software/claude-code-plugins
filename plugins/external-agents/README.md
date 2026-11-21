# external-agents

A Claude Code plugin that hands tasks and reviews to other vendors' official coding-agent CLIs
through their documented headless surfaces. Codex is the first CLI. Each CLI gets one skill; one
shared runner is the only code that calls a CLI.

It replaces OpenAI's `codex@openai-codex` plugin
([openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc), read as the upstream source;
none of its text or code is copied).

## Status

In progress: `run`, `review`, `status`, `result`, `cancel` and `update` work, and
`/external-agents:codex` drives them.

## Surface

- **`external-agents`**, on the Bash `PATH` while the plugin is enabled: `run`, `review`, `status`,
  `result`, `cancel` and `update`. `review:council` calls `external-agents review <product>`; nothing
  outside this plugin reads its install path or its scripts.
- **`/external-agents:codex`**: hands a task, an investigation or a review to Codex, in the
  foreground or background, and reads back, resumes or cancels its jobs.
- No hooks, no agents and no `commands/` folder: nothing runs until you or a council run asks.

claude.ai organization plugin sync skips this plugin, because it ships a top-level `bin/`
([org sync](https://claude.com/docs/plugins/org-sync)). It needs a local CLI, so it cannot run there
anyway.

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
