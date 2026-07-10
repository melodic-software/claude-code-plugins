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

| Channel | Env toggle | What it does |
|---|---|---|
| `bell` | `HOOK_DESKTOP_NOTIFICATION_BELL_ENABLED` | Audible terminal bell (bare `BEL`). |
| `terminal_notify` | `HOOK_DESKTOP_NOTIFICATION_TERMINAL_NOTIFY_ENABLED` | OSC 9 desktop notification, emitted via the hook's `terminalSequence` output (Claude Code v2.1.141+ writes it through its own terminal path). |
| `os_toast` | `HOOK_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED` | OS-native toast (see per-OS table). |

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

The hook runs on Bash 3.2+ and needs [`jq`](https://jqlang.github.io/jq/) on
`PATH`. macOS needs nothing further; Linux needs `libnotify` only for the
`os_toast` channel; Windows needs nothing (terminal channels only). Telemetry
timing uses `EPOCHREALTIME` (Bash 5.0+); on older bash the telemetry envelope is
skipped while notifications still fire.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install desktop-notification@melodic-software
```

## Configuration

This plugin has no `userConfig` — all of its variability is env-driven. Set any
toggle in your settings `env` block (values are read literally; changes
hot-reload):

```json
{
  "env": {
    "HOOK_DESKTOP_NOTIFICATION_BELL_ENABLED": "false",
    "HOOK_DESKTOP_NOTIFICATION_OS_TOAST_ENABLED": "false"
  }
}
```

### Disable without uninstalling

```json
{ "env": { "HOOK_DESKTOP_NOTIFICATION_ENABLED": "false" } }
```

## Telemetry (opt-in)

When the consumer sets `HOOK_TELEMETRY_SINK` to an executable, the hook emits one
[telemetry envelope](../../docs/conventions/hook-telemetry/README.md) per run —
`hook: "desktop-notification"`, `hook_event: "Notification"`, and a `data` payload
of `notification_type` plus the `channels` that fired. Unset → exact no-op.

## License

[MIT](../../LICENSE).
