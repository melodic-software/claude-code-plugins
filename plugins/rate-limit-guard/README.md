# rate-limit-guard

A Claude Code plugin that makes the machine's shared subscription rate-limit windows observable to
every session that needs them, so autonomous loop lanes can pause **before** hitting a limit and
resume on their own after the reset. Four parts:

- **Statusline shim** (`scripts/statusline-shim.sh`), the durable wiring target. Installed once to
  `~/.claude/rate-limit-guard/bin/`, it resolves whichever tee version is installed at run time, so
  a plugin update never requires re-wiring and an uninstall degrades to your statusline running
  alone. Pure Bash builtins: it adds no measurable time to a refresh.
- **Statusline tee** (`scripts/statusline-tee.sh`), a transparent wrapper around your statusline
  command. It atomically writes the session's `rate_limits` (both the 5-hour and 7-day windows),
  a `captured_at` timestamp, and the session-distinguishing fields to the fixed machine-scope
  contract path `~/.claude/rate-limit-guard/rate-limits.json`, once per drain cadence and only
  when the payload changed or the no-change floor expired, then passes your statusline through
  byte-for-byte. With no statusline configured it doubles as a minimal
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
- **An unchanged payload costs no rename.** When a refresh's snapshot body matches what is already
  on disk, `captured_at` aside, it takes no lock, stages no temp file and performs no rename. So an
  unchanged payload can leave the file, `captured_at` included, untouched for up to the skip floor:
  300 seconds by default (`RLG_TEE_NOCHANGE_FLOOR`), measured from the last real write by a
  `.last-write` stamp in the contract directory. That is half the reader contract's 10-minute
  staleness budget, so a session whose windows sit still still refreshes `captured_at` well before a
  reader could call it stale, and a changed payload is written on the next refresh regardless. The
  spool's 15-minute record sweep runs on the same 5-minute cadence rather than on every drain,
  tracked by `spool/.last-sweep`. Both stamps are writer-private: they hold epoch seconds, carry no
  session data, and readers ignore them. Every tuning knob the tee reads from the environment is
  validated as a plain integer before it reaches bash arithmetic and falls back to its default
  otherwise. The render path itself has been fork-free since the spool landed, which the suite
  asserts directly by tracing a non-elected render (`statusline-tee.test.sh`, "the zero-fork render
  path").
- **Multi-account operation is a narrowed gap, not yet a supported mode.** The snapshot names the
  account whose windows it carries in an `account.email` field, so a machine switching accounts
  mid-drain is now visible to a reader that checks it. Two things keep it a gap. The field is
  **absent** whenever the writer could not attribute the observation — no state file, no
  email-shaped value, a stdin `account*` key that wins instead, or a state file that is not
  strictly older than the chosen record's spool file, which means a switch may have happened in
  between — and no consuming lane acts on the field yet. An **equal** timestamp counts as "not
  strictly older": mtime resolution is coarse on several filesystems the writer runs on, so a
  same-tick login is indistinguishable there from a later one, and the writer omits rather than
  guess. The loop-lane convention §6 owns that framing; the reader contract states the four
  absence cases and the untrusted-value rule (`reference/reader-contract.md`, "Tee file shape").
  The wrapper still forwards a harness-supplied identity automatically when its own top-level key
  name contains `account`, and that value always wins over the writer's.

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
already-installed plugin that prints `already installed` and still writes the value. Never
uninstall to reconfigure: that drops the whole stored `pluginConfigs` entry and resets every
option to its manifest default. The verified-version record lives in the
[plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

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
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
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

## Measured cost

Measured 2026-09-02 on Windows/MSYS with Git Bash, both tees interleaved in one loop so each meets
the same machine load. Two lanes matter and they cost very different amounts: the steady render,
which every refresh pays, and the drain, which one elected refresh per cadence pays for the whole
machine. The floor is one `bash -c :` spawn, 45 ms and 57 ms on the two runs below, and a
spawn-equivalent is the tee's cost over the bare render divided by that floor.

| Lane | Before | After |
| --- | --- | --- |
| Drain, external commands | 7 | 3 |
| Drain, total process creations | 10 | 5 |
| Drain, spawn-equivalents | 8 to 10 | 5 to 6 |
| Steady render, spawn-equivalents | 1.2 to 1.3 | 1.1 to 1.5 |

The drain loses the rename, the snapshot lock's `mkdir` and `rmdir`, and the sweep's `find`. The
process-creation row counts the pure-bash forks the external-command row does not: the managed-scope
probe's two, unchanged, and the atomic write's `umask` subshell, which disappears along with the
write it wraps. The steady render is unchanged within measurement noise and sits well inside the
2 spawn-equivalent bar, because the spool had already reduced it to zero external processes.

## Tuning: `RLG_TEE_ASYNC`

Not a plugin option. A plain environment variable the statusline tee reads directly, so it sits
outside the generated block above: Claude Code does not prompt for it and no settings scope
carries it.

| Variable | Default | Effect |
| --- | --- | --- |
| `RLG_TEE_ASYNC` | `0` (off) | `1` detaches the snapshot write from the render, so the status line does not wait for it |

The snapshot is a side effect: nothing the status line prints depends on it, and the
[reader contract](reference/reader-contract.md) budgets ten minutes of staleness. Detaching skips
no work of its own. A refresh still takes the lock and writes unless the bounded no-change skip
applies. Detaching only stops the render waiting.

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
