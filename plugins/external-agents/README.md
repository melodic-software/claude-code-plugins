# external-agents

A Claude Code plugin that hands tasks and reviews to other vendors' official coding-agent CLIs
through their documented headless surfaces. Codex is the first CLI. Each CLI gets one skill; one
shared runner is the only code that calls a CLI.

It replaces OpenAI's `codex@openai-codex` plugin
([openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc), read as the upstream source;
none of its text or code is copied).

## Status

Scaffold only: the `external-agents` command prints its usage. The runner, the Codex skill and
council's switch-over follow in later changes.

## Surface

- **`external-agents`**, on the Bash `PATH` while the plugin is enabled: `run`, `review`, `status`,
  `result`, `cancel` and `update`. `review:council` calls `external-agents review <product>`; nothing
  outside this plugin reads its install path or its scripts.
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

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install external-agents@melodic-software
```
