# desktop-notification

A Claude Code plugin that alerts you the moment Claude needs your input. On a
`permission_prompt` or `idle_prompt` notification it emits up to three additive,
independently-toggleable channels: an audible terminal bell, an OSC 9 terminal
notification, and — on macOS and Linux — an OS-native desktop toast.

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
| macOS | [`osascript … display notification`](https://code-maven.com/display-notification-from-the-mac-command-line) | Built-in — no dependency. First run prompts to allow notifications for the terminal app. |
| Linux | [`notify-send`](https://man.archlinux.org/man/notify-send.1.en) (libnotify) | Install `libnotify-bin` (Debian/Ubuntu) or `libnotify` (Fedora). Absent → the `os_toast` channel is a silent no-op. |
| Windows / other | none | No OS-toast branch: a fire-and-forget hook process leaves no live activator host for a WinRT toast to render into, so it would never reliably surface. The `terminal_notify` channel (OSC 9) carries Windows attention — [Windows Terminal handles OSC 9](https://code.claude.com/docs/en/hooks). |

The OS toast body includes the current git branch when the project is a git
repository (e.g. `Waiting for your input — feat/my-branch`); outside a repo it is
just the message.

## Requirements

The hook runs on Bash 3.2+ (Git Bash on native Windows — install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows)) and
needs [`jq`](https://jqlang.github.io/jq/) on `PATH`; without jq, notifications
are disabled with a visible once-per-session notice. macOS needs nothing
further; Linux needs `libnotify` only for the `os_toast` channel; Windows needs
nothing (terminal channels only). Telemetry
timing uses `EPOCHREALTIME` (Bash 5.0+); on older bash the telemetry envelope is
skipped while notifications still fire.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install desktop-notification@melodic-software
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

Set them interactively with `/plugin configure desktop-notification`, or headless
on the install command:

```shell
claude plugin install desktop-notification@melodic-software --config desktop_notification_os_toast_enabled=false
```

These options are user-scoped (stored in your user settings, not the
project's). To silence notifications for a single repository, disable the whole
plugin in that project's `enabledPlugins` instead.

### Disable without uninstalling

Set `desktop_notification_enabled` to `false` (via `/plugin configure
desktop-notification` or `--config desktop_notification_enabled=false`).

## Telemetry (opt-in)

When the consumer sets `HOOK_TELEMETRY_SINK` to an executable, the hook emits one
[telemetry envelope](../../docs/conventions/hook-telemetry/README.md) per run —
`hook: "desktop-notification"`, `hook_event: "Notification"`, and a `data` payload
of `notification_type` plus the `channels` that fired. Unset → exact no-op.

## License

MIT (SPDX-License-Identifier: MIT). See the `LICENSE` file at the root of the
melodic-software/claude-code-plugins repository.
