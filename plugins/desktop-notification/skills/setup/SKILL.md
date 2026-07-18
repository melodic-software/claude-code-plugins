---
name: setup
description: "Verify the desktop-notification hook's runtime prerequisites and per-OS channel configuration for this machine. Use when: 'set up desktop-notification', 'configure desktop-notification', 'is desktop-notification working', notifications silently aren't firing, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform contract: `check` inspects and reports, `apply`
resolves. This plugin owns no consumer-project configuration — the only tunables are the
four native `userConfig` toggles (master + one per channel), and every remaining
prerequisite is a system tool or an OS package. So `apply` is pure guidance-and-verify
with **no write path**: it installs nothing and edits nothing.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
offers the resolution for each finding. Both are non-interactive — never prompt when the
action is given.

## `check` (read-only)

The hook scripts are the single source of truth for what they require and how they degrade:
`${CLAUDE_PLUGIN_ROOT}/hooks/desktop-notification.sh` and the shared
`${CLAUDE_PLUGIN_ROOT}/hooks/hook-utils.sh`. **Read them first** — probe what they actually
do, don't recite this file. Then run each probe via Bash and report a PASS/FAIL/INFO table
with one remediation line per FAIL. Do not modify anything.

When the plugin's toggle is disabled, every prerequisite absence downgrades from FAIL to
INFO — the hook exits through its enabled-gate before probing anything, so a deliberately
disabled plugin is not broken. Report the probes informationally and note that re-enabling
restores the FAIL semantics.

1. **Bash version** — check `${BASH_VERSION}` against the hook's documented floor (README
   Requirements: Bash 3.2+). INFO when below 5.0: `EPOCHREALTIME` is unset there, so the
   opt-in telemetry envelope is skipped while notifications still fire — a degrade, not a
   failure.
2. **`jq`** — `command -v jq`. FAIL if absent: without it the hook can neither classify the
   notification nor emit its terminal sequence, so it surfaces a once-per-session
   `systemMessage` notice and drops every notification for the session.
3. **Per-OS `os_toast` dependency** — detect the current OS family with `uname -s` and probe
   ONLY that family's requirement (the hook's `case "$(uname -s)"` does exactly this):
   - **Linux** — `command -v notify-send` (libnotify). FAIL only if the `os_toast` channel is
     enabled and it is absent; otherwise INFO. Absent → the `os_toast` channel is a
     documented silent no-op; remediation is the README's install hint (`libnotify-bin` on
     Debian/Ubuntu, `libnotify` on Fedora). The terminal channels are unaffected.
   - **macOS (Darwin)** — INFO: `osascript` is built-in, no dependency. Note the first toast
     prompts to allow notifications for the terminal app.
   - **Windows / other** — INFO: the hook has no `os_toast` branch on this platform (a
     fire-and-forget process leaves no live activator host for a WinRT toast). The
     `terminal_notify` OSC 9 channel carries attention here; nothing to install.
4. **Channel toggles** — report the effective value of all four native booleans (unexpanded
   or empty means the default `true`): master `${user_config.desktop_notification_enabled}`,
   `${user_config.desktop_notification_bell_enabled}`,
   `${user_config.desktop_notification_terminal_notify_enabled}`, and
   `${user_config.desktop_notification_os_toast_enabled}`. Call out when the master toggle is
   off (the whole hook is muted) or when the only channel that would fire on this OS is
   disabled.
5. **Hook registration** — INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL or actionable INFO offer the resolution — this skill installs
nothing and writes nothing, so every remediation is a pointer the user acts on:

- **missing `jq` / old Bash** — the platform install instructions from the README Requirements
  section. This skill never installs system packages.
- **missing `notify-send`** (Linux, `os_toast` enabled) — `sudo apt install libnotify-bin`
  (Debian/Ubuntu) or `sudo dnf install libnotify` (Fedora), per the README's per-OS table.
  Guidance only — the user runs it.
- **a toggle is off** — direct to `/plugin configure desktop-notification` or
  `claude plugin install desktop-notification@<marketplace> --config <key>=true`; these
  options are user-scoped, so this skill never writes user settings or `pluginConfigs`.

After the user reports acting on any system-tool remediation, re-run the relevant `check`
probe and report its actual result — never claim resolved on the user's say-so alone.
Re-running `apply` when everything already passes changes nothing and reports "already
configured".

## What this skill does NOT do

- Install `jq`, `libnotify`, or any system package, and never writes user settings or
  `pluginConfigs` — `apply` is guidance-and-verify with no write path.
- Fire a notification — a `permission_prompt` or `idle_prompt` exercises the hook end-to-end.
- Modify the plugin cache or the hook scripts.
