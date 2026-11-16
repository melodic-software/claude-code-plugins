# plugin-diagnostics

Detects and reports why installed plugins cannot run: hooks that fail to launch, and missing runtimes
or prerequisite tools. It is hooks only: no skills. It is on by default, and works whether or not any
other plugin is enabled.

## Contents

- [What it reports](#what-it-reports)
- [Install](#install)
- [Requirements](#requirements)
- [Configuration](#configuration)

## What it reports

| Hook | Event | Reports |
|---|---|---|
| `hook-failure-audit` | Stop | a hook that failed to launch or exited non-zero without Claude Code showing it, once per session per hook, as a `systemMessage` |
| node notice | SessionStart | that `node` is not on PATH, so hooks that launch through node do not run, once per session |
| prerequisites notice | SessionStart | for each enabled plugin whose `prerequisites.json` declares `session_probe`, the tools its hooks need that are missing, as one notice |

The two session-start rows follow the
[prerequisites contract § Hook notices](../../docs/contracts/prerequisites/README.md#hook-notices). The
node notice runs under `sh` or PowerShell and needs no node; the prerequisites notice launches node
through `lib/node-or-skip.sh`, so a machine without node gets the node notice and nothing else.

### The hook-failure audit

Its user-facing `systemMessage`
warning fires regardless of sink wiring (only its envelope needs a sink),
because its whole subject is failures nothing else surfaces: a hook that fails
to launch is a non-blocking error, the guarded tool call proceeds as if
approved, and the only durable trace is a transcript attachment no human reads
. It runs once per `Stop`, tails a bounded window of the session
transcript for `hook_non_blocking_error` attachments (structural match on the
attachment type, never substring), and warns once per session per distinct
failing hook registration, keyed on `hookName` plus the registered command because several plugins
share an event and matcher, re-warning when a new registration starts failing. It
lives in this
plugin, not in the plugin it might report on, deliberately: an in-plugin
detector shares its plugin's registration form and dies with it, which is
exactly how disk-hygiene's guard monitor missed the #1416 incident class.

Each failure record is classed one of four ways, and the warning gives each
class its own diagnosis and remedy:

- **launch failure**: stderr carries an exec-failure signature; the hook never
  ran.
- **stale config**: exit 127 and the whole stderr is bash's missing-script line
  (`bash: <path>: No such file or directory`). The session still runs hook
  config it loaded before a plugin update or an in-place edit deleted that
  script; the remedy is `/reload-plugins`, or a restart.
- **ambiguous**: exit 126 or 127 with neither of the above, so the registered
  command and the hook's own commands are both suspects.
- **completed non-zero exit**: the hook ran and failed.

Its budget share is stated as a **process count**, not a duration, and the host
is the reason. The [hook-budget
convention](../../docs/contracts/hook-budget/README.md) states each
always-on hook's budget as k x S plus measured work (k = fewest spawns, S = one no-op spawn's time), not a fixed millisecond figure, and on the host in #3508 one
process creation costs 180-2,841 ms (median 1,108 ms at 501 concurrent
processes), so the count is what decides whether the set fits and a duration
measured anywhere else does not transfer. On a turn with **no** hook failure
recorded, the common case, the hook costs **9 process creations and 4 program
execs**: one `wc` for the tail-cap decision, one `grep` pre-filter that opens
the transcript directly, and two `jq` passes inside the synced `hook-utils.sh`.
The creations above that are subshell forks inside the same shared library. It
was 18 creations and 6 execs before #3512. Counts are measured with `strace -ff
-e trace=clone,clone3,fork,vfork,execve`, not `bash -x`: a command substitution
whose command carries its own redirection forks a subshell that xtrace cannot
see, and those forks were most of the cost. `hook-failure-audit.test.sh`
asserts both ceilings. Windows Git Bash, the host the convention binds to,
measured S (the bash spawn floor) at 33 ms on 2026-09-30, through the bash the
launcher spawns (20 ms on the PATH bash), but the hook-failure-audit wall
there is still unmeasured for this row, so its spawn-equivalents (hook wall
divided by the same-run S) are still owed.

The audit also emits the [hook-telemetry envelope](../../docs/contracts/hook-telemetry/README.md) as
`hook-failure-audit`, which reaches a sink only where one is wired, such as session-telemetry's.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install plugin-diagnostics@melodic-software
```

## Requirements

The hook-failure audit is a Bash script (Git Bash on native Windows) run in shell form, needing no
node, and uses `jq`; without jq it skips its work. The prerequisites notice needs `node` and is
skipped silently without it, since the node notice already says node is missing.

## Configuration

`hook_failure_audit_enabled` (default on) switches the hook-failure audit off. `stdin_read_timeout`
(seconds, default `2`) is an idle bound on reading the hook payload, after which the audit skips.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `hook_failure_audit_enabled` | boolean | `true` | Warns once per session per hook when the transcript records hook launch or exec failures Claude Code never surfaced. On by default. |
| `stdin_read_timeout` | number<br>*min 1* | `2` | Idle bound on reading the hook payload from stdin: how long the pipe may go silent before the hook gives up and fails open. Default 2. |

### How to set these

Set the options above for `plugin-diagnostics@<marketplace>`, replacing `<marketplace>` with the
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
