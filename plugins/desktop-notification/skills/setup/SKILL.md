---
description: "Verify the desktop-notification hook's runtime prerequisites and per-OS channel configuration for this machine. Use when: 'set up desktop-notification', 'configure desktop-notification', 'is desktop-notification working', notifications silently aren't firing, or the hook reported a missing prerequisite. Actions: check (read-only verification, default) | apply (resolve what check found). Re-runnable and safe."
argument-hint: "[check|apply]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(uname -s*)"
  - "Bash(command -v node*)"
  - "Bash(command -v jq*)"
shell: bash
---

## Pre-computed context

`check`'s `node` and `jq` probes and OS-family detection ran at load time. Read these rows instead
of re-issuing them. The `node` and `jq` rows show the tool's path, or `absent` when missing; the
`uname -s` row shows the kernel name, or `unknown` when it fails to run:

- `node`: !`command -v node 2>/dev/null || echo absent`
- `jq`: !`command -v jq 2>/dev/null || echo absent`
- `uname -s`: !`uname -s 2>/dev/null || echo unknown`

A row reading `[shell command execution disabled by policy]` carries no result: run that probe via
Bash instead.

- **Pointer**: for the placeholder a skipped load-time command leaves, fetch
  [skills § Inject dynamic context](https://code.claude.com/docs/en/skills#inject-dynamic-context)
  live.
- **As of**: 2026-11-11
- **Recheck trigger**: the placeholder text changes.

## Purpose

Thin check-centric setup per the uniform setup contract (`docs/plugin-philosophy.md`
"Setup is explicit and repeatable" in the marketplace repository): `check` inspects and
reports, `apply` resolves. This plugin owns no consumer-project configuration. The only
tunables are the five native `userConfig` toggles (master, one per channel, mod-toast forwarding), and every
remaining prerequisite is a system tool or an OS package. So `apply` is pure
guidance-and-verify with **no write path**: it installs nothing and edits nothing.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then
offers the resolution for each finding. Both are non-interactive. Never prompt when the
action is given.

## `check` (read-only)

The hook script and the shared library it sources are the single source of truth for what this
plugin requires and how it degrades: `${CLAUDE_PLUGIN_ROOT}/hooks/desktop-notification.sh` and
`${CLAUDE_PLUGIN_ROOT}/hooks/hook-utils.sh`.

**Read it first.** Probe what it actually does, don't recite this file. Then read the pre-computed
`node`, `jq` and `uname -s` rows, run the remaining probes via Bash, and report a PASS/FAIL/INFO table with
one remediation line per FAIL. Do not modify anything.
Read each option value from this text; never put a `${user_config.*}` string in a shell command.
Open plugin files by the `${CLAUDE_PLUGIN_ROOT}` paths this skill names; never Glob or Grep the plugin directory.

When the plugin's toggle is disabled, every prerequisite absence except Node.js (step 3)
downgrades from FAIL to INFO. The hook exits through its enabled-gate before probing anything, so
a deliberately disabled plugin is not broken. Report the probes informationally and note that
re-enabling restores the FAIL semantics. A missing Node.js stays FAIL in either state: every hook
row launches `node`, and the gate runs only after `hooks/exec-bash.mjs` starts.

1. **Bash version**. Check `${BASH_VERSION}` against the hook's documented floor (README
   Requirements: Bash 3.2+). INFO when below 5.0: `EPOCHREALTIME` is unset there, so the
   opt-in telemetry envelope is skipped while notifications still fire, a degrade, not a
   failure.
2. **`jq`**. The pre-computed `jq` row. FAIL if absent: without it the hook can neither classify the
   notification nor emit its terminal sequence, so it drops every notification without a notice.
   This check is where a missing jq surfaces: the hook cannot report it to the user or the model.
   Pointer: [Notification](https://code.claude.com/docs/en/hooks#notification).
3. **Node.js**. The pre-computed `node` row. FAIL if absent: every hook row launches through
   `node hooks/exec-bash.mjs`, so without it the hook does not launch and no notification fires.
   The probe runs through the Bash tool, so it works when the launcher cannot. Remediation: install
   Node.js from `https://nodejs.org/en/download`, or from the platform package manager. Node is a
   prerequisite separate from Claude Code. Pointer: [Install with
   npm](https://code.claude.com/docs/en/setup#install-with-npm) and [Exec form and shell
   form](https://code.claude.com/docs/en/hooks#exec-form-and-shell-form).
4. **Per-OS `os_toast` dependency**. Take the current OS family from the pre-computed `uname -s` row
   and probe ONLY that family's requirement (the hook's `case "$(uname -s)"` does exactly this):
   - **Linux**. `command -v notify-send` (libnotify). FAIL only if the `os_toast` channel is
     enabled and it is absent; otherwise INFO. Absent → the `os_toast` channel is a
     documented silent no-op; remediation is the missing-`notify-send` entry under `apply`.
     The terminal channels are unaffected.
   - **macOS (Darwin)**. INFO: `osascript` is built-in, no dependency. Note the first toast
     prompts to allow notifications for the terminal app.
   - **Windows / other**. INFO: the hook has no `os_toast` branch on this platform (a
     fire-and-forget process leaves no live activator host for a WinRT toast). The
     `terminal_notify` OSC 9 channel carries attention here; nothing to install.
5. **Channel toggles**. Report the effective value of all five native booleans (unexpanded
   or empty means the default `true`): master `${user_config.desktop_notification_enabled}`,
   `${user_config.desktop_notification_bell_enabled}`, `${user_config.desktop_notification_terminal_notify_enabled}`,
   `${user_config.desktop_notification_os_toast_enabled}`, and
   `${user_config.desktop_notification_forward_toasts_enabled}`. Call out when the master toggle is
   off (the whole hook is muted) or when the only channel that would fire on this OS is
   disabled.
6. **Hook registration**. INFO: confirm the plugin is enabled for this project
   (`/plugin` → Installed) rather than parsing settings files.

## `apply` (idempotent)

Run `check`, then for each FAIL or actionable INFO offer the resolution. This skill installs
nothing and writes nothing, so every remediation is a pointer the user acts on:

- **missing Node.js**. `https://nodejs.org/en/download` or the platform package manager.
- **missing `jq` / old Bash**. The platform install instructions from the README Requirements
  section. This skill never installs system packages.
- **missing `notify-send`** (Linux, `os_toast` enabled). `sudo apt install libnotify-bin`
  (Debian/Ubuntu) or `sudo dnf install libnotify` (Fedora). Guidance only. The user runs it.
- **a toggle is off**. Set that toggle's key to `true` through Claude Code's native flow,
  interactively with `/plugin configure desktop-notification@<marketplace>` or by a headless route,
  as the marketplace's plugin-reconfiguration convention gives them in
  [§ The routes](../../reference/plugin-reconfiguration.md#the-routes)
  (it owns the verified-version record). Apply the scope and failure-signal caveats in its
  [§ Caveats every setup skill's short form carries](../../reference/plugin-reconfiguration.md#caveats-every-setup-skills-short-form-carries).
  Read both sections and print what they give, the fallback route, its behavior on an
  already-installed plugin and the scope to pass included, rather than only naming them, and
  leave out the verified-version record.
  Never uninstall to reconfigure; that section links what an uninstall deletes. These options are
  personal `userConfig` values, so this skill never writes user settings or `pluginConfigs`.
  Afterwards rerun `check` in a **fresh session**, since a same-session `check` can still show the
  old value, and report the observed effective value, never an unobserved change.

  - **Pointer**: for the headless command's flags, how it reports a saved or refused value, and
    when a saved value applies, fetch
    [plugin CLI reference § plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
    live.

After the user reports acting on any system-tool remediation, re-run the relevant `check`
probe live via Bash (a pre-computed row predates the remediation) and report its actual
result. Never claim resolved on the user's say-so alone.
Re-running `apply` when everything already passes changes nothing and reports "already
configured".

## What this skill does NOT do

- Install Node.js, `jq`, `libnotify`, or any system package. `apply` is guidance-and-verify with no
  write path.
- Fire a notification. A `permission_prompt` or `idle_prompt` exercises the hook end-to-end.
- Write the plugin cache, Claude Code user settings, or `pluginConfigs`. Nor the hook scripts.
