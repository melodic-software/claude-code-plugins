# desktop-notification

A Claude Code plugin that alerts you the moment Claude needs your input. On a
`permission_prompt` or `idle_prompt` notification it emits up to three additive,
independently-toggleable channels: an audible terminal bell, an OSC 9 terminal
notification, and, on macOS and Linux, an OS-native desktop toast.

## Behavior

- **Fires on attention prompts.** We match the `permission_prompt` and
  `idle_prompt` notification types, plus the `plugin_notification` this plugin's
  mod raises (title `desktop-notification`, see [Forwarding mod toasts](#forwarding-mod-toasts));
  every other notification is a silent no-op.
- **Advisory, never blocking.** The hook always exits `0`; a Notification hook is
  not a gate.
- **Pointer**: the notification types and what a Notification hook can return are
  in [Notification](https://code.claude.com/docs/en/hooks#notification). **As of**:
  2026-10-11. **Recheck trigger**: that section renames either type, lets a
  Notification hook block, stops discarding its `systemMessage`, or is renamed.
- **Three additive channels**, each default on and independently mutable:

| Channel | Option | What it does |
|---|---|---|
| `bell` | `desktop_notification_bell_enabled` | Audible terminal bell (bare `BEL`). |
| `terminal_notify` | `desktop_notification_terminal_notify_enabled` | OSC 9 desktop notification, emitted via the hook's `terminalSequence` output, which Claude Code writes through its own terminal path. |
| `os_toast` | `desktop_notification_os_toast_enabled` | OS-native toast (see per-OS table). |

- **Pointer**: how `terminalSequence` output is written and which terminals handle
  OSC 9 are in
  [Emit terminal notifications](https://code.claude.com/docs/en/hooks#emit-terminal-notifications).
  **As of**: 2026-10-11. **Recheck trigger**: that section changes how
  `terminalSequence` output is written, documents a Windows toast path, or is
  renamed.

### Per-OS `os_toast` behavior

| OS | Tool | Requirement |
|---|---|---|
| macOS | [`osascript … display notification`](https://code-maven.com/display-notification-from-the-mac-command-line) | Built-in. No dependency. First run prompts to allow notifications for the terminal app. |
| Linux | [`notify-send`](https://man.archlinux.org/man/notify-send.1.en) (libnotify) | Install `libnotify-bin` (Debian/Ubuntu) or `libnotify` (Fedora). Without it, the `os_toast` channel is a silent no-op. |
| Windows / other | none | No OS-toast branch: a fire-and-forget hook process leaves no live activator host for a WinRT toast to render into, so it would never reliably surface. The `terminal_notify` channel (OSC 9) carries Windows attention; which Windows terminals handle OSC 9 is read at the Emit terminal notifications pointer record above, which carries this cell's as-of date and recheck trigger. |

The OS toast body includes the current git branch when the project is a git
repository (e.g. `Waiting for your input — feat/my-branch`); outside a repo it is
just the message.

### Forwarding mod toasts

A hooks module (`hooks/register.ts`) hooks `ui.toast`. For each toast any mod shows,
it raises `$.ui.notify` with the title `desktop-notification`, then calls `next` so
the toast still shows. Claude Code fires a `plugin_notification` Notification for
that call, and the hook above sends it through the same channels, headed
`Claude Code`. A `plugin_notification` from any other mod is left alone.
`desktop_notification_forward_toasts_enabled` turns forwarding off;
`desktop_notification_enabled` set to `false`, or all three channel options set to
`false`, turns it off too. `$.ui.notify` also alerts through Claude Code's own
`preferredNotifChannel`, so a forwarded toast can alert twice; that setting set to
`notifications_disabled` leaves only the plugin's channels.

- **Probe** (Claude Code 2.1.312, two-plugin mod test under `claude plugin test`):
  a user-tier mod's `ui.toast` hook hears toasts from mods at the `prepend`,
  `user` and `append` tiers, and its own. Hooks run in tier order (`prepend`,
  `user`, `append`), and toasts from two senders arrive in the order fired. Not
  probed: toasts Claude Code raises itself, and a live interactive or `-p` session.
- **Needs** Claude Code 2.1.295 or later with mods on, the first release with
  `$.ui.notify` ([changelog](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md#21295));
  mods themselves load from 2.1.287. The settings hook runs on any version.
- **Pointer**: the `ui.toast` hook and `$.ui.notify` are in
  [Mods API](https://code.claude.com/docs/en/plugins/mods/api.md#show-something-without-starting-a-turn),
  and the `plugin_notification` title rule is in
  [Notification](https://code.claude.com/docs/en/hooks#notification). **As of**:
  2026-10-28. **Recheck trigger**: either section renames `ui.toast`,
  `$.ui.notify` or `plugin_notification`, or changes where the hook's `title` comes from.

## Requirements

The hook runs on Bash 3.2+. On native Windows, install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so Git Bash is
available. It needs Node.js on `PATH`: the hook launches through `node hooks/exec-bash.mjs`, and
a Claude Code install does not guarantee Node, so without it the hook does not launch and
notifications do not fire ([install Node.js](https://nodejs.org/en/download)). It also needs [`jq`](https://jqlang.github.io/jq/) on `PATH`; without jq, notifications
are disabled and `/desktop-notification:check` reports it, because a Notification hook has no notice
channel of its own. Relay: what it can return is in the Notification pointer record under
[Behavior](#behavior). **As of**: 2026-10-11. **Recheck trigger**: that record leaves Behavior,
or its own recheck trigger fires. macOS needs nothing
further; Linux needs `libnotify` only for the `os_toast` channel; Windows needs
nothing (terminal channels only). Telemetry
timing uses `EPOCHREALTIME` (Bash 5.0+); on older bash the telemetry envelope is
skipped while notifications still fire.

- **Pointer**: whether an install brings Node is in
  [Install with npm](https://code.claude.com/docs/en/setup#install-with-npm), and how the hook's
  `node` command is launched is in
  [Exec form and shell form](https://code.claude.com/docs/en/hooks#exec-form-and-shell-form).
  **As of**: 2026-10-11. **Recheck trigger**: the first section changes whether the native binary
  ships or uses Node, the second changes how exec form launches `command`, or either is renamed.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install desktop-notification@<marketplace>
```

Then verify prerequisites with `/desktop-notification:setup check`. `/desktop-notification:check` reports whether `node` and `jq` resolve.

## Configuration

Every channel is toggled by its own `userConfig` boolean (default **on**; set to
`false` to mute that channel). Mute the OS toast and keep the rest:

| Option | What it controls |
|---|---|
| `desktop_notification_enabled` | The whole notification hook. |
| `desktop_notification_bell_enabled` | The `bell` channel. |
| `desktop_notification_terminal_notify_enabled` | The `terminal_notify` (OSC 9) channel. |
| `desktop_notification_os_toast_enabled` | The `os_toast` channel. |
| `desktop_notification_forward_toasts_enabled` | Forwarding mod toasts as notifications. |

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

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `desktop_notification_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_ENABLED` | Runs the whole notification hook. On by default; off mutes every channel below. |
| `desktop_notification_bell_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_BELL_ENABLED` | Audible terminal bell (a bare BEL). On by default. |
| `desktop_notification_terminal_notify_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED` | OSC 9 terminal notification emitted through the hook's terminalSequence output. On by default. |
| `desktop_notification_os_toast_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED` | OS-native desktop toast: macOS (osascript) or Linux (requires notify-send). On by default. No effect on Windows, where the terminal channels carry the alert. |
| `desktop_notification_forward_toasts_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_DESKTOP_NOTIFICATION_FORWARD_TOASTS_ENABLED` | Sends each toast a mod shows as a native notification through the hooks module, and the toast still shows. On by default. Needs Claude Code 2.1.295 or later with mods on. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure desktop-notification@<marketplace>`.
2. **Headless.** Save the values with [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure),
   run from the project the plugin is installed in. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin configure desktop-notification@<marketplace> --values-stdin < values.json
   ```

   `values.json` holds a JSON object of strings, booleans included:

   ```json
   {"desktop_notification_enabled": "<value>"}
   ```

   This is the preferred headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md), which records its
   limits: the Claude Code version it needs, which install it finds, how it rejects a bad
   value, and why a session started before the change keeps the old value until a fresh
   session starts. Do **not** `claude plugin uninstall` to reconfigure: see
   [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).

   The fallback the convention names, for a Claude Code release without
   `plugin configure`, reruns the install with the new value, passing the scope
   `claude plugin list` reports for this plugin:

   ```shell
   claude plugin install desktop-notification@<marketplace> -s <scope> --config desktop_notification_enabled=<value>
   ```

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
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

   The [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs)
   entry names the settings scopes Claude Code reads this key from.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself; set the value through one
of the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure): the `--values-stdin` flag's reference entry
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## Telemetry (opt-in)

When the consumer sets `HOOK_TELEMETRY_SINK` to an executable, the hook emits one
[telemetry envelope](../../docs/contracts/hook-telemetry/README.md) per run.
`hook: "desktop-notification"`, `hook_event: "Notification"`, and a `data` payload
of `notification_type` plus the `channels` that fired. When it is unset, the hook is an exact no-op.

## License

MIT (SPDX-License-Identifier: MIT).
