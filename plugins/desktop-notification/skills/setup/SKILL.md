---
description: "Verify the desktop-notification hook's runtime prerequisites and per-OS channel configuration for this machine. Use when: 'set up desktop-notification', 'configure desktop-notification', 'is desktop-notification working', notifications silently aren't firing, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "check | apply"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/PLUGIN-PHILOSOPHY.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. This plugin owns no consumer-project configuration — the only
tunables are the four native `userConfig` toggles (master + one per channel), and every
remaining prerequisite is a system tool or an OS package. So `apply` is pure
guidance-and-verify with **no write path**: it installs nothing and edits nothing.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
offers the resolution for each finding. Both are non-interactive — never prompt when the
action is given.

## `check` (read-only)

The hook script and the shared library it sources are the single source of truth for what this
plugin requires and how it degrades: `${CLAUDE_PLUGIN_ROOT}/hooks/desktop-notification.sh` and
`${CLAUDE_PLUGIN_ROOT}/hooks/hook-utils.sh`.

**Read it first** — probe what it actually does, don't recite this file. Then run each probe via
Bash and report a PASS/FAIL/INFO table with one remediation line per FAIL. Do not modify anything.

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
- **a toggle is off** — direct to `/plugin configure desktop-notification` (interactive,
  any time). Headless: rerun the install with the new value —
  `claude plugin install desktop-notification@<marketplace> -s <scope> --config <key>=true`.
  Against an already-installed plugin it prints `already installed` **and still writes the value**
  — verified on Claude Code 2.1.240 (a non-sensitive option at `user` scope: a non-default value
  written to an installed plugin, then restored). The short-circuit is about the install, not the
  config write. Re-verify before relying on it outside those conditions — a `sensitive` option, or
  `project`/`local` scope, were not covered. Do **not** uninstall to reconfigure: uninstalling
  drops this plugin's entire stored `pluginConfigs` entry, resetting every option in the README's
  Options reference table to its manifest default, not only the toggle being flipped. `-s`
  defaults to `user`, so pass the install scope `claude plugin list` reports for this plugin, and
  run from that project's directory for a `project`/`local` scope, or the write lands at a scope
  that does not load. These options are personal `userConfig` values, so this skill never writes
  user settings or `pluginConfigs`.
  Afterwards, keep the two claims apart. The write is issued and the stored value is what you
  passed; the RUNNING session's behavior is not. The rendered `${user_config.*}` is injected at
  skill load and each hook receives its `CLAUDE_PLUGIN_OPTION_*` from an environment fixed at
  session start, so a same-session `check` still reports the OLD value — reporting that as a
  failed write would be wrong. Verify the effective value by rerunning `check` in a **fresh
  session**, and never claim an unobserved change.

After the user reports acting on any system-tool remediation, re-run the relevant `check`
probe and report its actual result — never claim resolved on the user's say-so alone.
Re-running `apply` when everything already passes changes nothing and reports "already
configured".

## What this skill does NOT do

- Install `jq`, `libnotify`, or any system package — `apply` is guidance-and-verify with no
  write path.
- Fire a notification — a `permission_prompt` or `idle_prompt` exercises the hook end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. Nor the hook scripts.
