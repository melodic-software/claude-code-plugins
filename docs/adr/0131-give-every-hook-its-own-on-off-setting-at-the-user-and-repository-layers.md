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
   at the user layer (`userConfig`) and the repository layer (`docs/conventions/<plugin>.yaml`).
   The hook's own script reads it, resolving every layer before deciding.
2. **The user's own value wins for that user.** An explicit user `false` turns the hook off
   whatever the repository says; the repository value is the default for everyone who has not set
   their own; the plugin default decides when neither is set. This reverses config-cascade's
   team-over-`userConfig` order for these keys, a declared deviation listed in config-cascade's
   Deviations. For a guard whose off state loosens a security control, a repository value can only
   turn it on, and only the user's own layer turns it off: the policy-floor class's protection
   against the repository layer, without its condition 2, since the user's own `false` still wins.
3. **`<name>_enabled` stays affirmative for `userConfig` options and convention-file keys.**
   [Configuration switch naming](../standards/configuration-switch-naming.md) names a default-on
   switch `<THING>_DISABLED` so an unset switch never turns the behavior off; these keys always
   resolve to a declared default, the standard's case of a boolean that always holds a value. A hook
   that reads an environment variable of its own follows the standard: `<THING>_DISABLED` for a
   default-on behavior, `<THING>_ENABLED` for a default-off one.
4. **Three levels:** the per-hook setting, Claude Code's plugin enable and disable, and
   `disableAllHooks`.
5. **A git hook reads the user layer from the plugin's `pluginConfigs` entry in Claude Code's user
   settings**, where Claude Code stores option values, so one value set in `/config` governs both
   kinds of hook.
6. **Prose calls it an on/off setting**, never a toggle or a flag.
7. **The contract lives in `docs/contracts/hook-enablement/`**, with a pointer page at
   `docs/conventions/hook-enablement/README.md` in the shape of the hook-budget one.

## Alternatives considered

- **(a) Plugin-level setting only.** Fewer keys, but one noisy hook then costs the operator the
  plugin's other hooks. Not chosen.
- **(b) "Toggle" or "flag" in prose.** "Toggle" carries the feature-toggle lifecycle of a
  short-lived switch, and "flag" collides with command-line flags; Claude Code's settings reference
  describes its keys as turning something on or off. Not chosen.
- **(c) A git-config key for git hooks.** Works without Claude Code installed, but it is a second
  name for the same setting in a second place. Not chosen.
- **(d) User layer only.** A repository could not turn a hook off for every contributor. Not chosen.
- **(e) Repository value wins, config-cascade's order.** A repository could force a hook on for a
  contributor who turned it off. Not chosen.
- **(f) `<name>_disabled` for default-on hooks.** The switch-naming standard's rule protects an
  unset switch, and these keys always resolve to a declared default. Not chosen.

## Consequences

- Each hook script resolves two layers before doing work, which counts against the hook budget.
- A hook that treats an unset user layer as its plugin default without reading the repository value
  does not conform; an exit on an explicit user `false` does.
- The plugins listed in #18921 need an option per hook.
