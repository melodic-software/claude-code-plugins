# rate-limit-guard

A Claude Code plugin that makes the machine's shared subscription rate-limit windows observable to
every session that needs them, so autonomous loop lanes can pause **before** hitting a limit and
resume on their own after the reset. Four parts:

- **Statusline shim** (`scripts/statusline-shim.sh`), the durable wiring target. Installed once to
  `~/.claude/rate-limit-guard/bin/`, it resolves whichever tee version is installed at run time, so
  a plugin update never requires re-wiring and an uninstall degrades to your statusline running
  alone. Pure Bash builtins: it adds no measurable time to a refresh.
- **Statusline tee** (`scripts/statusline-tee.sh`), a transparent wrapper around your statusline
  command. Each refresh it atomically writes the session's `rate_limits` (both the 5-hour and
  7-day windows), a `captured_at` timestamp, and the session-distinguishing fields to the fixed
  machine-scope contract path `~/.claude/rate-limit-guard/rate-limits.json`, then passes your
  statusline through byte-for-byte. With no statusline configured it doubles as a minimal
  standalone statusline.
- **StopFailure hook** (`hooks/record-rate-limit-stop.sh`), the reactive fallback. When a turn
  ends on a rate-limit API error, it appends a detection record to
  `~/.claude/rate-limit-guard/stop-events.jsonl`. StopFailure output and exit codes are ignored by
  the harness, so the hook is side-effect-only by design.
- **Reader contract** (`reference/reader-contract.md`), the authoritative consumer contract: the
  fixed tee path, the 90%-of-either-window pause threshold, the staleness rule, pause-end
  semantics, capability-detect fail-open, and drain-then-pause.

## Behavior

- **Transparent by contract.** No tee outcome ever changes the wrapped statusline's output or
  exit code, including missing `jq`, an unwritable path, or a rename blocked by a concurrent
  reader. Missing `jq` is
  surfaced as a visible one-line notice, never a silent skip.
- **Atomic, last-writer-wins snapshot.** Concurrent sessions write one path; readers never see torn
  JSON (temp file + rename, with a brief retry for the Windows rename-over-open-target case).
- **Fail-open capability detection.** Sessions whose auth exposes no `rate_limits` (API-key,
  enterprise) tee an honest snapshot without the key; consumers treat that as unknown and run
  reactive-only rather than throttling on fabricated data. Cloud / remote sessions with no
  statusline producer typically have no tee file at all. That is the same unknown → reactive-only
  classification, documented as the expected degraded mode in
  [`reference/reader-contract.md`](reference/reader-contract.md) ("Cloud / remote sessions"), with
  a documented residual that a live cloud producer is out of scope until one exists.
- **Multi-account operation is a known gap, not a supported mode.** The snapshot carries no account
  identifier (none exists in the statusline schema today), so a machine switching accounts mid-drain
  feeds wrong windows to running lanes and the guard cannot detect it. The loop-lane convention §6
  owns that framing; the reader contract cites it. The wrapper adopts a future account-identifying
  field automatically only when its own top-level key name contains `account`; every other shape
  needs a writer change (`reference/reader-contract.md`, "Tee file shape").

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install rate-limit-guard@<marketplace>
```

The StopFailure hook is active immediately. The statusline tee needs two operator steps, both
one-time:

1. `/rate-limit-guard:setup apply` installs the statusline shim to
   `~/.claude/rate-limit-guard/bin/statusline-shim.sh`. The shim is inert until step 2.
2. `/rate-limit-guard:setup check` verifies prerequisites and prints the exact `settings.json`
   statusline edit (wrapping your existing command, or standalone) for you to apply. The plugin
   never edits your settings itself.

You wire the **shim**, not the tee, and that wiring is permanent: `${CLAUDE_PLUGIN_ROOT}` is
version-pinned and the old version directory is pruned ~14 days after an update, so a statusline
wired straight to `<plugin-root>/scripts/statusline-tee.sh` silently stops teeing on the next
version bump and then takes the whole statusline down when the path disappears. The shim resolves
the newest installed tee at run time, so plugin updates need no re-wiring, and it passes your
statusline through unchanged when no tee is installed (including after uninstall).

Running alongside `context-guard`? The tees are transparent wrappers, so they nest, each through
its own shim, with the innermost command still owning stdout and the exit code. Both setup skills
print that combined form.

## Requirements

The scripts run on Bash (Git Bash on native Windows; install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows); the statusline wiring
invokes `bash` explicitly) and need [`jq`](https://jqlang.org/download/) on `PATH` for the tee and
the standalone statusline. Proactive window data requires Claude.ai subscription auth (Pro/Max).
`rate_limits` appears only there, per the
[statusline reference](https://code.claude.com/docs/en/statusline); on other auth the guard is
reactive-only. The tee updates only while an interactive session refreshes the statusline.

Cost: the tee adds roughly 0.6–0.9 s per statusline refresh on Windows/Git Bash (process-spawn
bound, `jq` and `date`), and correspondingly less on native POSIX shells. The statusline is not on
the input path, so this is display latency, not typing latency; `refreshInterval` in your settings
governs how often it runs.

## Configuration

One `userConfig` option:

| Option | What it controls |
|---|---|
| `rate_limit_guard_enabled` | Kill switch for the StopFailure detection hook **and** the statusline tee's snapshot write (default `true`). |

Set it with `/plugin configure rate-limit-guard@<marketplace>`, or headless via `claude plugin install
rate-limit-guard@<marketplace> -s <scope> --config rate_limit_guard_enabled=false`, against an
already-installed plugin that prints `already installed` and still writes the value, verified on
Claude Code 2.1.240 for a non-sensitive option at `user` scope. Never uninstall to reconfigure: that
drops the whole stored `pluginConfigs` entry and resets every option to its manifest default.

**Where the switch is read from.** The StopFailure hook receives it the ordinary way, as
`CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED`. The statusline tee cannot: it is invoked by
absolute path from the operator's own `statusLine` setting, and Claude Code exports those variables
to *hook* processes only, so the tee reads `pluginConfigs` from the settings files directly. Its
precedence is **managed settings → user settings → environment**, highest first. A managed
`rate_limit_guard_enabled: false` is an organization's policy and wins over any user value. Every
degraded read (no settings file, no `jq`, malformed JSON) leaves the tee enabled, and no outcome of
that gate ever changes what your statusline prints.

The tee path and the 90% pause threshold are deliberately **not** configurable: they are contract
constants that cross-plugin consumers inline from the
[reader contract](reference/reader-contract.md); a per-user override would silently split the
writer from its readers. The kill switch stops the tee's *write* while leaving the wrapper
transparent; removing the wrapper itself is the operator's edit to their `statusLine`; disabling
everything is `enabledPlugins` / uninstall.

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `rate_limit_guard_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED` | Master switch for the StopFailure detection hook and the statusline tee's snapshot write; read from managed settings first, then user settings |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure rate-limit-guard@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install rate-limit-guard@<marketplace> -s <scope> --config rate_limit_guard_enabled=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value — verified on Claude Code 2.1.240,
   for a non-sensitive option at `user` scope, by writing a non-default value to an
   installed plugin and restoring it. The short-circuit message is about the install,
   not the config write. That has not been verified for a `sensitive` option or for
   `project`/`local` scope. Do **not** `claude plugin uninstall` to
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
       "rate-limit-guard@<marketplace>": {
         "options": {
           "rate_limit_guard_enabled": <value>
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

## Consumers

Written for the loop-lane convention's three lanes (work-items `work-loop` and `attend-queue`,
source-control `babysit-loop`), which inline the reader contract's operable floor. Any session or
tool on the machine may read the same files under the same contract.

## Tuning: `RLG_TEE_ASYNC`

Not a plugin option. A plain environment variable the statusline tee reads directly, so it sits
outside the generated block above: Claude Code does not prompt for it and no settings scope
carries it.

| Variable | Default | Effect |
| --- | --- | --- |
| `RLG_TEE_ASYNC` | `0` (off) | `1` detaches the snapshot write from the render, so the status line does not wait for it |

The snapshot is a side effect: nothing the status line prints depends on it, and the
[reader contract](reference/reader-contract.md) budgets ten minutes of staleness. Detaching skips
no work. Every refresh still takes the lock and writes. Detaching only stops the render waiting.

**Whether that helps depends on how many sessions you keep open, not on your refresh interval.**
MSYS has no native `fork()`, so forking a bash subshell holding the payload costs 75–200 ms on
Windows, against ~24 ms to exec a small binary. Detaching does not make the work cheaper; it buys
back the render's critical path by paying a fork more expensive than the execs it steps around,
and it lets successive refreshes overlap instead of serialise. Measured on Windows, 24 cores,
status line + tee:

| | sync (default) | async |
| --- | --- | --- |
| One session, refreshes 1 s apart | 660 ms | **222 ms** |
| Ten sessions at 1 Hz, median | **2265 ms** | 4476 ms |
| Ten sessions, peak `bash` processes | **50** | 71 |

Turn it on if you work in one or two windows. Leave it off if you run many. At ten sessions it
roughly doubles both latency and process count. On Linux and macOS, where `fork()` is cheap, the
crossover sits much further out; the numbers above are the Windows worst case.

## License

MIT (SPDX-License-Identifier: MIT).
