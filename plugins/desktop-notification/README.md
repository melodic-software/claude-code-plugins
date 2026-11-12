# desktop-notification

A Claude Code plugin that alerts you the moment Claude needs your input. On a
`permission_prompt` or `idle_prompt` notification it emits up to three additive,
independently-toggleable channels: an audible terminal bell, an OSC 9 terminal
notification, and, on macOS and Linux, an OS-native desktop toast.

## Behavior

- **Fires on attention prompts.** The hook matches the `permission_prompt` and
  `idle_prompt` notification types, plus the `plugin_notification` this plugin's
  mod raises (title `desktop-notification`, see [Forwarding mod toasts](#forwarding-mod-toasts));
  every other notification is a silent no-op.
- **Advisory, never blocking.** The hook always exits `0`; a Notification hook is
  not a gate.
- **Pointer**: the notification types and what a Notification hook can return are
  in [Notification](https://code.claude.com/docs/en/hooks#notification).
- **Three additive channels**, each default on and independently mutable:

| Channel | Option | What it does |
|---|---|---|
| `bell` | `desktop_notification_bell_enabled` | Audible terminal bell (bare `BEL`). |
| `terminal_notify` | `desktop_notification_terminal_notify_enabled` | OSC 9 desktop notification, emitted via the hook's `terminalSequence` output, which Claude Code writes through its own terminal path. |
| `os_toast` | `desktop_notification_os_toast_enabled` | OS-native toast (see per-OS table). |

- **Pointer**: how `terminalSequence` output is written and which terminals handle
  OSC 9 are in
  [Emit terminal notifications](https://code.claude.com/docs/en/hooks#emit-terminal-notifications).

### Per-OS `os_toast` behavior

| OS | Tool | Requirement |
|---|---|---|
| macOS | [`osascript … display notification`](https://code-maven.com/display-notification-from-the-mac-command-line) | Built-in. No dependency. First run prompts to allow notifications for the terminal app. |
| Linux | [`notify-send`](https://man.archlinux.org/man/notify-send.1.en#DESCRIPTION) | Needs `notify-send` on `PATH`. Without it, the `os_toast` channel is a silent no-op. |
| Windows / other | none | No OS-toast branch: a fire-and-forget hook process leaves no live activator host for a WinRT toast to render into, so it would never reliably surface. The `terminal_notify` channel (OSC 9) carries Windows attention; which Windows terminals handle OSC 9 is read at the Emit terminal notifications pointer record above. |

- **Pointer**: when checking what `notify-send` is and the project that ships it, fetch
  [notify-send(1)](https://man.archlinux.org/man/notify-send.1.en#DESCRIPTION) live.

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
  [Notification](https://code.claude.com/docs/en/hooks#notification).

## Requirements

The hook runs on Bash 3.2+. On native Windows, install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so Git Bash is
available. It needs Node.js on `PATH`: the hook launches through `node hooks/exec-bash.mjs`, and
a Claude Code install does not guarantee Node, so without it the hook does not launch and
notifications do not fire ([install Node.js](https://nodejs.org/en/download)). It also needs [`jq`](https://jqlang.github.io/jq/) on `PATH`; without jq, notifications
are disabled and the bundled checker reports it, because a Notification hook has no notice
channel of its own. Relay: what it can return is in the Notification pointer record under
[Behavior](#behavior). macOS needs nothing further; Linux needs `notify-send` only for the `os_toast` channel; Windows needs
nothing (terminal channels only). Telemetry
timing uses `EPOCHREALTIME` (Bash 5.0+); on older bash the telemetry envelope is
skipped while notifications still fire.

- **Pointer**: whether an install brings Node is in
  [Install with npm](https://code.claude.com/docs/en/setup#install-with-npm), and how the hook's
  `node` command is launched is in
  [Exec form and shell form](https://code.claude.com/docs/en/hooks#exec-form-and-shell-form).

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install desktop-notification@melodic-software
```

Then verify prerequisites with `/desktop-notification:setup check`. `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"` reports whether `node` and `jq` resolve.

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

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `desktop_notification_enabled` | boolean | `true` | Runs the whole notification hook. On by default; off mutes every channel below. |
| `desktop_notification_bell_enabled` | boolean | `true` | Audible terminal bell (a bare BEL). On by default. |
| `desktop_notification_terminal_notify_enabled` | boolean | `true` | OSC 9 terminal notification emitted through the hook's terminalSequence output. On by default. |
| `desktop_notification_os_toast_enabled` | boolean | `true` | OS-native desktop toast: macOS (osascript) or Linux (requires notify-send). On by default. No effect on Windows, where the terminal channels carry the alert. |
| `desktop_notification_forward_toasts_enabled` | boolean | `true` | Sends each toast a mod shows as a native notification through the hooks module, and the toast still shows. On by default. Needs Claude Code 2.1.295 or later with mods on. |

### How to set these

Set the options above for `desktop-notification@<marketplace>`, replacing `<marketplace>` with the
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

## Telemetry (opt-in)

When the consumer sets `HOOK_TELEMETRY_SINK` to an executable, the hook emits one
[telemetry envelope](../../docs/contracts/hook-telemetry/README.md) per run.
`hook: "desktop-notification"`, `hook_event: "Notification"`, and a `data` payload
of `notification_type` plus the `channels` that fired. When it is unset, the hook is an exact no-op.

## License

MIT (SPDX-License-Identifier: MIT).
