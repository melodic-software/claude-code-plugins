# desktop-notification

A Claude Code plugin that alerts you the moment Claude needs your input. On a
`permission_prompt` or `idle_prompt` notification it emits up to three additive,
independently-toggleable channels: an audible terminal bell, an OSC 9 terminal
notification, and, on macOS and Linux, an OS-native desktop toast.

## Behavior

- **Fires on attention prompts.** Only the `permission_prompt` and `idle_prompt`
  notification types trigger it; every other notification is a silent no-op.
- **Advisory, never blocking.** The hook always exits `0` (Notification hooks
  cannot block).
- **Three additive channels**, each default on and independently mutable:

| Channel | Option | What it does |
|---|---|---|
| `bell` | `desktop_notification_bell_enabled` | Audible terminal bell (bare `BEL`). |
| `terminal_notify` | `desktop_notification_terminal_notify_enabled` | OSC 9 desktop notification, emitted via the hook's `terminalSequence` output (Claude Code v2.1.141+ writes it through its own terminal path). |
| `os_toast` | `desktop_notification_os_toast_enabled` | OS-native toast (see per-OS table). |

Platform facts verified 2026-07-18: hook `terminalSequence` output landed in Claude Code
v2.1.141 per the [Claude Code changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md);
channel semantics per the [hooks reference](https://code.claude.com/docs/en/hooks).

### Per-OS `os_toast` behavior

| OS | Tool | Requirement |
|---|---|---|
| macOS | [`osascript … display notification`](https://code-maven.com/display-notification-from-the-mac-command-line) | Built-in. No dependency. First run prompts to allow notifications for the terminal app. |
| Linux | [`notify-send`](https://man.archlinux.org/man/notify-send.1.en) (libnotify) | Install `libnotify-bin` (Debian/Ubuntu) or `libnotify` (Fedora). Absent → the `os_toast` channel is a silent no-op. |
| Windows / other | none | No OS-toast branch: a fire-and-forget hook process leaves no live activator host for a WinRT toast to render into, so it would never reliably surface. The `terminal_notify` channel (OSC 9) carries Windows attention. [Windows Terminal handles OSC 9](https://code.claude.com/docs/en/hooks). |

The OS toast body includes the current git branch when the project is a git
repository (e.g. `Waiting for your input — feat/my-branch`); outside a repo it is
just the message.

## Requirements

The hook runs on Bash 3.2+. On native Windows, install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so Git Bash is
available. It needs [`jq`](https://jqlang.github.io/jq/) on `PATH`; without jq, notifications
are disabled with a visible once-per-session notice. macOS needs nothing
further; Linux needs `libnotify` only for the `os_toast` channel; Windows needs
nothing (terminal channels only). Telemetry
timing uses `EPOCHREALTIME` (Bash 5.0+); on older bash the telemetry envelope is
skipped while notifications still fire.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install desktop-notification@<marketplace>
```

Then verify prerequisites with `/desktop-notification:setup check`.

## Configuration

Every channel is toggled by its own `userConfig` boolean (default **on**; set to
`false` to mute that channel). Mute the OS toast and keep the rest:

| Option | What it controls |
|---|---|
| `desktop_notification_enabled` | Master toggle for the whole hook. |
| `desktop_notification_bell_enabled` | The `bell` channel. |
| `desktop_notification_terminal_notify_enabled` | The `terminal_notify` (OSC 9) channel. |
| `desktop_notification_os_toast_enabled` | The `os_toast` channel. |

Set them interactively with `/plugin configure desktop-notification@<marketplace>`, or headless
on the install command:

```shell
claude plugin install desktop-notification@<marketplace> --config desktop_notification_os_toast_enabled=false
```

Option scoping (user vs project settings, and the per-repository escape hatch)
per "How to set these" below.

### Disable without uninstalling

Set `desktop_notification_enabled` to `false` (via `/plugin configure
desktop-notification@<marketplace>` or `--config desktop_notification_enabled=false`).

## Telemetry (opt-in)

When the consumer sets `HOOK_TELEMETRY_SINK` to an executable, the hook emits one
[telemetry envelope](../../docs/conventions/hook-telemetry/README.md) per run.
`hook: "desktop-notification"`, `hook_event: "Notification"`, and a `data` payload
of `notification_type` plus the `channels` that fired. Unset → exact no-op.

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `desktop_notification_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_ENABLED` | Master switch for the whole notification hook |
| `desktop_notification_bell_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED` | Audible terminal bell (bare BEL) |
| `desktop_notification_terminal_notify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED` | OSC 9 terminal notification emitted via the hook's terminalSequence output |
| `desktop_notification_os_toast_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED` | OS-native desktop toast (macOS/Linux) |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure desktop-notification@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install desktop-notification@<marketplace> -s <scope> --config desktop_notification_enabled=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value — verified on Claude Code 2.1.240,
   for a non-sensitive option at `user` scope, by writing a non-default value to an
   installed plugin and restoring it. The short-circuit message is about the install,
   not the config write. That has not been verified for a `sensitive` option or for
   `project`/`local` scope. Do **not** `claude plugin uninstall` in order to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin.

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior — a check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "desktop-notification@<marketplace>": {
         "options": {
           "desktop_notification_enabled": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install) — the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
<!-- ai-slop-ignore-end -->

## License

MIT (SPDX-License-Identifier: MIT).
