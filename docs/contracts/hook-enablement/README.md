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
- **Naming against the switch standard.** [Configuration switch naming](https://github.com/melodic-software/standards/blob/main/standards/engineering/configuration-switch-naming.md)
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
- **Subagent-confining gates.** A hook that confines a subagent to an allowed command or host set
  (`discovery`'s `docs-fetcher-gate`, and `multi-agent`'s `drift-checker-fetch-gate`,
  `docs-fetcher-gate` and `registry-fetcher-gate`) carries no `<name>_enabled` setting and is
  exempt from the adoption check.
- **Cost.** Reading the repository file on every fire counts against the
  [hook budget](../hook-budget/README.md#the-hook-enablement-helper).

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

### The shared helper

[`lib/hook-enabled.sh`](../../../lib/hook-enabled.sh) resolves one key across every layer above, so
no plugin writes the precedence itself. Its suite is `lib/hook-enabled.test.sh`. For hooks modules
(`modules` in `hooks/hooks.json`), [`lib/mod-hook-enabled.ts`](../../../lib/mod-hook-enabled.ts)
(suite `lib/mod-hook-enabled.test.mjs`) provides the same precedence and `security: true`
policy-floor semantics in-process with zero subprocess spawns (`createModEnablement` plus
`refreshModEnablement($, gate, e.cwd)` in `session.start`, reading `$.settings.read` across
`policy`, `flag`, and `user` to separate explicit user values from manifest defaults filled into
`options`, then reading `<root>/<convention-home>/<plugin>.yaml` after resolving the repository's
bound convention home through `$.fs.stat` and `$.fs.read`). To adopt the shell helper, a plugin:

1. Registers a copy in `scripts/shared-copies.txt`, for example
   `lib/hook-enabled.sh plugins/<plugin>/hooks/hook-enabled.sh`, and runs
   `scripts/sync-shared-copies.sh` ([ADR 0019](../../adr/0019-share-code-across-plugins-by-vendoring-with-a-sync-gate.md)).
   Edits go to the canonical copy in `lib/`.
2. Sources the copy in the hook's own script and, before any work, calls
   `hook_enabled::resolve <plugin> <key> <default>`, with `<default>` the option's manifest
   `default`, and exits 0 only when it returns 1:
   `rc=0; hook_enabled::resolve <plugin> <key> <default> || rc=$?; ((rc != 1)) || exit 0`.

`resolve` returns 0 when the hook runs, 1 when it is off and 2 on a usage error, which it names on
stderr. Exiting only on 1 keeps a hook with a broken call running, so a guard does not go quiet. It
also names each dropped value on stderr. Flags:

| Flag | Use |
|---|---|
| none | A Claude Code hook: user layer from `CLAUDE_PLUGIN_OPTION_<KEY>`, repository layer under `CLAUDE_PROJECT_DIR` |
| `--git-hook` | A git hook: user layer from `pluginConfigs`, repository layer at `git rev-parse --show-toplevel` |
| `--security` | A [security control](#the-per-hook-setting): a repository `false` and a `CLAUDE_PLUGIN_OPTION_<KEY>=false` are ignored (a `true` from either still turns the guard on). The user's `false` turns the guard off only from `pluginConfigs` in the `settings.json` beside the install's `plugins/cache` (with `--git-hook`, the user settings file above), so a Claude Code hook copy outside the install cache cannot be turned off. A `pluginConfigs` value in managed settings wins over both; on Linux a managed `false` counts only from a root-owned file no one else can write |
| `--root DIR` | The project root, in place of `CLAUDE_PROJECT_DIR` or git's top level |
| `--home DIR` | The convention home relative to the root, in place of `docs/conventions` |

Its cost per fire is under
[hook budget, The hook-enablement helper](../hook-budget/README.md#the-hook-enablement-helper).

## Wording

Prose calls the per-hook setting an **on/off setting**, never a toggle or a flag: Claude Code's own
settings reference describes its keys as turning something on or off, "flag" collides with
command-line flags, and "toggle" carries the feature-toggle lifecycle of a short-lived switch. Option
titles already ban both words ([plugin-option-naming](../plugin-option-naming/README.md#titles)).

## Adopters

A plugin conforms when each hook it ships has its own `<name>_enabled` option and its script
resolves both layers. Plugins that ship hooks with no such option are listed in
[#18921](https://github.com/melodic-software/claude-code-plugins/issues/18921).

### The adoption check

`bash scripts/list-hook-enablement-gaps.sh` prints, one per line, each plugin whose
`hooks/hooks.json` declares a non-exempt hook and whose `plugin.json` `userConfig` declares no
boolean option ending in `_enabled`. A hook here is an event handler under `hooks` or an entry
under `modules`, so a plugin that ships only a module is listed too. The script filters out the
four exempt [subagent-confining gates](#the-per-hook-setting) by plugin and leading `args` prefix,
so a plugin whose only hooks are exempt (`multi-agent`) is not listed, while any non-exempt hook in
the same plugin (such as `discovery`'s `webfetch-truncation.mjs`) still puts the plugin on the
list. The script exits `2` when a `hooks.json` or
`plugin.json` is empty or not valid JSON, naming the file, and when no plugin declares a non-exempt
hook. Its suite, `scripts/list-hook-enablement-gaps.test.sh`, runs in CI's shell test lane, on
every change to a `hooks.json` or `plugin.json` under `plugins/`, and fails when the repository's
list differs from the suite's `PENDING` list. A plugin that adopts its option leaves
both lists in the same change. A new plugin that ships a hook ships its option with it.

A hook maps to its key by [the key rule](#the-per-hook-setting): a hook named after its plugin maps to
the plugin's name in snake_case plus `_enabled` (`bash-format` to `bash_format_enabled`), and any
other hook maps to its own name in snake_case plus `_enabled` (`hooks/block-no-verify.sh` to
`block_no_verify_enabled`). The check reads plugins, not single hooks: one such option takes a
plugin off the list. To verify a per-plugin change, check that the plugin left the list, then check
by hand each hook in its `hooks.json` against the key rule, and confirm its script resolves both
layers. The check does not read `git-hooks/`.

The retrofit tracked in
[#18921](https://github.com/melodic-software/claude-code-plugins/issues/18921) is accepted when the
script lists no plugin.
