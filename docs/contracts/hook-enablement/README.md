# Hook enablement: an on/off setting for every hook

Owner doc for **how an operator turns a plugin's hooks on and off**. Every hook a plugin ships, a
Claude Code hook in `hooks/hooks.json` or a git hook in `git-hooks/`, has its own on/off setting. The
`hook-*` family splits the rest: [hook-config-delivery](../hook-config-delivery/README.md) owns the
channel that carries a `userConfig` value into a hook process, [config-cascade](../config-cascade/README.md)
owns how layers resolve, and [plugin-option-naming](../plugin-option-naming/README.md) owns an
option's title and description text. The decision is
[ADR 0131](../../adr/0131-give-every-hook-its-own-on-off-setting-at-the-user-and-repository-layers.md).

## Three levels

| Level | Turns off | Mechanism |
|---|---|---|
| One hook | that hook alone | its `<name>_enabled` setting, read by the hook's own script (below) |
| One plugin | every hook and every other component of that plugin | Claude Code's plugin enable and disable ([`enabledPlugins`](https://code.claude.com/docs/en/settings-reference#enabledplugins)) |
| All hooks | every Claude Code hook | Claude Code's [`disableAllHooks`](https://code.claude.com/docs/en/settings-reference#disableallhooks) |

Claude Code has no per-hook off switch of its own, so the first level is this repository's.

**Record.** Claim: the hooks page states "There is no way to disable an individual hook while
keeping it in the configuration." Basis:
<https://code.claude.com/docs/en/hooks#disable-or-remove-hooks>. As of: 2026-11-24 (Claude Code
2.1.331). Recheck: that section adds a per-hook setting, or a Claude Code release note names one.
When it does, this doc points at the upstream setting and the per-hook key becomes its fallback.

## The per-hook setting

- **Key.** `<name>_enabled`, a boolean, where `<name>` is the hook's name in snake_case: the plugin's
  name for a hook named after its plugin (`bash_format_enabled`), else the hook's own
  (`observer_enabled`, `block_no_verify_enabled`). One key per hook; a key is never shared by two
  hooks with different purposes. Title and description follow
  [plugin-option-naming](../plugin-option-naming/README.md#titles).
- **Naming against the switch standard.** [Configuration switch naming](../../standards/configuration-switch-naming.md)
  names a default-on switch `<THING>_DISABLED` so that leaving it unset never turns the behavior
  off. A `userConfig` option or convention-file key always resolves to the default the plugin
  declares, so it has no unset state to protect: it is the standard's case of a boolean that always
  holds a value, which stays affirmative, hence `<name>_enabled` whatever the default. A hook that
  reads an environment variable of its own, not the `CLAUDE_PLUGIN_OPTION_<KEY>` that carries the
  option, follows the standard: `<THING>_DISABLED` for a default-on behavior, `<THING>_ENABLED` for
  a default-off one.
- **Default.** The plugin chooses it per hook and declares it as the option's `default`. A hook that
  starts work the operator did not ask for (a background process, a network call) defaults off.
- **Layers.** Lowest first: the plugin default; the user layer, the plugin's `userConfig` option of
  that key; the repository layer, the same key in `docs/conventions/<plugin>.yaml` (or the
  repository's bound convention home). An invalid value (anything but an unquoted `true` or
  `false`) is named with its file or option and dropped, per
  [config-cascade, The layers](../config-cascade/README.md#the-layers).
- **Precedence.** The user's own value, when the user has set one, wins for that user: an explicit
  `false` turns the hook off whatever the repository says. Otherwise the repository value decides,
  so a repository sets the default for every contributor who has not set their own. Otherwise the
  plugin default decides. The user layer is set only when the user chose a value: Claude Code
  exports no `CLAUDE_PLUGIN_OPTION_<KEY>` for an unset option
  ([hook-config-delivery, fact 3](../hook-config-delivery/README.md#verified-upstream-behavior-version-pinned)),
  and an unset option has no `pluginConfigs` entry.
- **Deviation from config-cascade.** Config-cascade puts the team layer above `userConfig`, the
  later layer winning. This key reverses that one pair, so a repository cannot force a hook back
  on for someone who turned it off; it is a declared deviation, listed in
  [config-cascade, Deviations](../config-cascade/README.md#deviations). The repository layer still
  refines the plugin default.
- **Who reads it.** The hook's own script, before it does any work. It resolves every layer before
  deciding: a hook that treats an unset user layer as the plugin default without reading the
  repository value does not conform.
- **Security controls.** For a guard whose off state loosens a security control, a repository
  value can only turn the guard on (a repository `false` is ignored), and only the user's own layer
  turns it off. This takes the repository half of the
  [policy-floor class](../config-cascade/README.md#sanctioned-exception-class-policy-floor-precedence-inversion),
  a floor the repository cannot loosen, and departs from its condition 2: the user's own `false`
  still takes effect for that user, per the precedence above.
- **Cost.** Reading the repository file on every fire counts against the
  [hook budget](../hook-budget/README.md).

## How the setting reaches the hook

### Claude Code hooks

The user layer arrives through the channel
[hook-config-delivery's decision rule](../hook-config-delivery/README.md#the-decision-rule) picks
for the hook (`CLAUDE_PLUGIN_OPTION_<KEY>` for a plugin `hooks.json` hook). The script reads the
repository layer from the project root Claude Code passes it.

### Git hooks

Git starts a git hook, not Claude Code, so no `CLAUDE_PLUGIN_OPTION_<KEY>` reaches it. The script
reads the same key from both layers itself:

- **User layer:** the plugin's entry under `pluginConfigs` in the user's Claude Code settings,
  where Claude Code stores non-sensitive option values
  ([Where values are stored](https://code.claude.com/docs/en/plugins/manifest-reference#where-values-are-stored),
  [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs)). An operator
  sets it once in `/config`, and the Claude Code hook and the git hook read one value. With no
  settings file or no entry, the layer is unset.
- **Repository layer:** `docs/conventions/<plugin>.yaml` at the repository's top level, the
  directory git runs the hook in.

A git-config key was the alternative: it works without Claude Code installed, but it would be a
second name for the same setting in a second place, and the two would drift.

The other two levels for git hooks are the hook manager's: a plugin's git hooks leave a clone when
its entry is removed, and the hook manager's own skip turns them all off for a run. For the
lefthook remote this marketplace ships, the per-clone skip of one job and declining an entry are in
[Adopting the git-hook entries](../check-placement/adopting-git-hooks.md), and lefthook's
[`LEFTHOOK`](https://lefthook.dev/usage/envs/LEFTHOOK) variable skips every hook for one command.

## Wording

Prose calls the per-hook setting an **on/off setting**, never a toggle or a flag: Claude Code's own
settings reference describes its keys as turning something on or off, "flag" collides with
command-line flags, and "toggle" carries the feature-toggle lifecycle of a short-lived switch. Option
titles already ban both words ([plugin-option-naming](../plugin-option-naming/README.md#titles)).

## Adopters

A plugin conforms when each hook it ships has its own `<name>_enabled` option and its script
resolves both layers. Plugins that ship hooks with no such option are listed in
[#18921](https://github.com/melodic-software/claude-code-plugins/issues/18921).
