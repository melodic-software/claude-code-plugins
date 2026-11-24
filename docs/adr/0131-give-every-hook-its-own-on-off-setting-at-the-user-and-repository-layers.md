# Give every hook its own on/off setting at the user and repository layers

- Status: accepted
- Date: 2026-11-24
- Related: owner interview, 2026-11-24; [hook-enablement](../contracts/hook-enablement/README.md)
  (the convention); [#18921](https://github.com/melodic-software/claude-code-plugins/issues/18921)
  (plugins still without the setting)

## Context

An operator who wants one hook off has two Claude Code controls, and both are wider: disabling the
plugin turns off every component it ships, and `disableAllHooks` turns off every hook. The hooks
page says there is no way to disable an individual hook while keeping it in the configuration
([Disable or remove hooks](https://code.claude.com/docs/en/hooks#disable-or-remove-hooks), read
2026-11-24). Some plugins already ship a per-hook `*_enabled` option; 11 of the 31 that ship
`hooks/hooks.json` ship none, and the git hooks have no setting at all.

## Decision

1. **Every hook, Claude Code and git hooks alike, has its own boolean `<name>_enabled` setting**,
   at the user layer (`userConfig`) and the repository layer (`docs/conventions/<plugin>.yaml`),
   resolved later-layer-wins through the config-cascade layers. The hook's own script reads it.
2. **Three levels:** the per-hook setting, Claude Code's plugin enable and disable, and
   `disableAllHooks`.
3. **A git hook reads the user layer from the plugin's `pluginConfigs` entry in Claude Code's user
   settings**, where Claude Code stores option values, so one value set in `/config` governs both
   kinds of hook.
4. **Prose calls it an on/off setting**, never a toggle or a flag.

## Alternatives considered

- **(a) Plugin-level setting only.** Fewer keys, but one noisy hook then costs the operator the
  plugin's other hooks. Not chosen.
- **(b) "Toggle" or "flag" in prose.** "Toggle" carries the feature-toggle lifecycle of a
  short-lived switch, and "flag" collides with command-line flags; Claude Code's settings reference
  describes its keys as turning something on or off. Not chosen.
- **(c) A git-config key for git hooks.** Works without Claude Code installed, but it is a second
  name for the same setting in a second place. Not chosen.
- **(d) User layer only.** A repository could not turn a hook off for every contributor. Not chosen.

## Consequences

- Each hook script resolves two layers before doing work, which counts against the hook budget.
- An early exit on the user value alone no longer conforms, since a repository value can turn the
  hook back on.
- The plugins listed in #18921 need an option per hook.
