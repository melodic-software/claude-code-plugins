# rate-limit-guard

A Claude Code plugin that tells Claude, and every session on the machine that reads its file, where
the account's shared subscription rate-limit windows stand, so Claude can plan around a limit
before it hits one and autonomous loop lanes can pause **before** a limit and resume on their own
after the reset. Three parts:

- **Hooks module** (`hooks/register.tsx`), a mod that Claude Code runs in its own process. It tells
  Claude at boundaries when a window approaches or reaches the pause edge and when it resets, shows
  you a toast when that happens, can draw the figures in a band row (off by default), answers a
  status tool, and writes the windows to the fixed machine-scope file
  `~/.claude/rate-limit-guard/rate-limits.json` in interactive and headless sessions alike. It needs Claude Code 2.1.287 or later; older builds are unsupported.
- **StopFailure hook** (`hooks/record-rate-limit-stop.sh`), the reactive fallback. When a turn
  ends on a rate-limit API error, it appends a detection record to
  `~/.claude/rate-limit-guard/stop-events.jsonl`. StopFailure output and exit codes are ignored by
  the harness, so the hook is side-effect-only by design.
- **Reader contract** (`reference/reader-contract.md`), the authoritative consumer contract: the
  fixed file path, the 95%-of-either-window pause threshold, the staleness rule, pause-end
  semantics, capability-detect fail-open, and drain-then-pause.

## Upgrading from a version with the statusline tee

Versions before 0.12.0 wrote the file through a statusline tee and a shim you wired into your own
`statusLine`. The module replaces both, and the plugin needs no wiring. After updating:

1. Run `/rate-limit-guard:setup`. It finds a tee that still runs (by the stamp files a tee writes
   and the cached plugin versions that still hold one) and every route that reaches it: a
   `statusLine` naming the shim or tee, a wrapper script such as a dotfiles status line
   entrypoint, or an installed shim copy.
2. Follow the unwire steps it prints. It shows your `statusLine` command with only the guard shims
   removed, so your own status line renderer stays exactly as it was, and the leftover files to
   delete. It never edits your settings or scripts itself.
3. Stop and restart sessions and lanes started before the update: they keep running what they
   loaded.

## The module

The module tells Claude where the account stands against its rate limits, tells you when a window
changes, can draw the figures in a band row, answers a status tool, and writes the contract file,
in interactive, `-p`, `--bg` and `/loop` sessions alike. Tested with `claude plugin test` and live on Claude Code 2.1.288: interactive
terminal sessions, `-p` runs, `--bg` and `/loop` lanes, side by side with the retired tee, a
mods-off session, and native Windows. The Desktop app and VS Code were not run.

### Lines to Claude

A line goes to Claude only at a boundary, appended to the context of a main-thread tool result or
of a prompt; a crossing seen when a turn ends reaches Claude with the next prompt. Per window
(5-hour and 7-day), with the default options:

| When | Line |
|---|---|
| The window reaches the approach mark (90%) | once per window, "nearing 95%" |
| The window reaches the line threshold (95%) | once per window, "at 95%", with the reset time and "Keep working." |
| The window resets (its reset time passes, or it leaves the reading) after reaching the threshold | once; the approach and threshold lines can then fire again |
| After a compaction (not the precompute kind), and after `/resume` or `/branch` | the verdict for every window, once |
| After `/clear`, and when the module loads into a session that already has turns (a `--resume` launch, a reload after an options change, a hooks-worker restart) | the verdict for each window at or above the threshold, once; nothing when none is |

Use only rises within a window, so a reading that dips below a mark sends nothing and does not
re-arm that mark's line. No other tool call or prompt carries a line. Each window gets its own
line, for example `rate-limit-guard: 5-hour window at 95%, resets at 2026-10-03 21:00 UTC. Keep
working.`; when several windows reach the threshold together, only the last line ends "Keep
working.". No line tells Claude to pause: an interactive session
[waits out a usage limit](https://code.claude.com/docs/en/interactive-mode#wait-for-a-usage-limit-to-reset)
and continues on its own. Every line carries its verdict; `rate_limit_line_data` chooses what
goes with it: the window's name (`window`), its use (`percent`) and its reset time (`reset`). Without `window` the line says "a
rate-limit window". A line never carries the account email or the session name. Subagents get no
line. The line threshold is a line setting only: the loop lanes' pause edge stays 95% (see the
[reader contract](reference/reader-contract.md)).

### Window changes shown to you

When a window rises from an earlier reading to the approach mark or the line threshold, or resets
after reaching the threshold, the module shows a toast for 4 seconds, such as `5h at the 95% pause
edge · resets 21:00 UTC`, and writes one transcript line Claude does not read, ending
`· more: /rate-limit-guard`. A window's first reading since the module loaded or the window reset is
never toasted, and neither is a restatement after a compaction, a resume, `/clear` or a reload:
those only restate the verdict to Claude. Windows belong to the account, so a rise across `/clear`
or a resume is a change and is toasted. The toast does not depend on `rate_limit_lines_enabled`. `rate_limit_guard_toast` set to
`false` drops the toast and keeps the transcript line. Outside the terminal (the Desktop app, VS
Code, mobile), where toast drawing is unverified, the change also shows as a single row above the
prompt, covering every window that changed, until your next prompt.

### Operator mode

With `rate_limit_report_mode` set to `operator`, a turn a person started by typing (or through the
Remote Control bridge) gets no line. When that turn ends, the line is offered as the prompt box's
suggestion (Tab takes it) and shown as a notice row above the prompt, on every surface, wrapped
rather than cut off. With text in the box, only the notice row shows, and the suggestion is offered
again once the box is empty. Where nobody can take a suggestion, the line goes to Claude as in
automatic mode: `-p` and SDK turns, `/loop` and scheduled turns, task notifications and other
non-typed turns, a session with no drawing surface (such as the VS Code panel), and a suggestion
the session reports it cannot show. The row and a shown suggestion are your channel for a held
line, so it gets a toast and a transcript line only when you never had either: its first offer
could not show, or a survey hid the row until the line went to Claude. A suggestion that showed
but was not taken goes to Claude as the automatic line at the next turn no person started; a turn
a person starts drops it unsent.

Upstream's render-sites table lists the band's site, `AbovePrompt`, as drawn in the terminal and
the Desktop app. No probe of this plugin ran in the Desktop app or VS Code, so the band, the
notice rows, the toast and the suggestion there are untested.

- **Pointer**: [mods reference: render sites](https://code.claude.com/docs/en/plugins/mods/reference#render-sites).
- **As of**: 2026-10-03, Claude Code 2.1.288.
- **Recheck trigger**: the `AbovePrompt` row changes the apps it lists, or a Desktop run of this
  plugin is made.

A `--bg` session reports its first prompt as typed, so in operator mode a `--bg` lane gets no line
from that turn; its line reaches Claude at the lane's next turn no person started. A lane that
wants the lines at once may start its session with its own options through `--settings`, which can
set any key user settings can, including the plugin's `pluginConfigs` entry:
`{"pluginConfigs": {"rate-limit-guard@<marketplace>": {"options":
{"rate_limit_report_mode": "automatic"}}}}` (a `--plugin-dir` copy is keyed `<name>@inline`).

- **Pointer**: [settings: change a setting for one session](https://code.claude.com/docs/en/settings#change-a-setting-for-one-session)
  and the `pluginConfigs` row of
  [mods reference: settings and environment variables](https://code.claude.com/docs/en/plugins/mods/reference#settings-and-environment-variables).
- **As of**: 2026-10-03, Claude Code 2.1.288.
- **Recheck trigger**: either section changes the scope `pluginConfigs` is read from.

### The /rate-limit-guard command, band row and status tool

`/rate-limit-guard` with no argument prints each window's use, verdict and reset time, the line
threshold and approach mark, whether the band row and the toast are on, the snapshot path and a
link to this README.

The band row above the prompt is off by default. When on, it shows `5h <x>% | 7d <y>%`, with `-`
for a window that has no reading yet. Context use is context-guard's row, not this one.
`rate_limit_guard_band` set to `true` turns it on for every session; `/rate-limit-guard band on`,
`band off`, or a bare `band` (toggle) changes it for the current session. Claude can call
`mcp__rate-limit-guard__status` for the exact figures from the last API response: every window the
response reported, with its verdict, and, behind a Claude gateway, the `spend_limit` window, which
is never written to the contract file.

### Snapshot writes

The module writes `~/.claude/rate-limit-guard/rate-limits.json` through `lib/write-snapshot.mjs`,
run with `node`, so the file is replaced atomically on Linux, macOS and native Windows. It writes
at once when a window moves a whole point, appears, leaves or resets, and otherwise at most once
every 300 seconds across the machine, checked from main-thread tool results, each measurement after
a turn, a 60-second timer that runs only while a turn runs, and the session's end. It never writes
from a turn a task notification started (a paused lane's own Monitor tick), and it follows the
plugin's on/off switch and `rate_limit_guard_enabled`. The body carries `captured_at`,
`session_id`, the windows, and `account.email` only when the account in the state file at the write
is the one it held at the last API response (a startup quota check counts); it never carries
`session_name` or `spend_limit`. A session with no windows writes a windowless body, which never
replaces a file that has windows.

Process cost: an event that writes nothing starts no process; each write starts one `node`
process. Mods can start host processes in the CLI only; where they cannot, the module writes
nothing and logs that once to the debug log.

### Where mods are off

Below Claude Code 2.1.287, under `disableAllHooks`, with `--bare`, when mods are switched off
remotely, or after the hooks worker crashes, the module does not run: no lines, no band, no status
tool, no module writes. The StopFailure hook still records, and readers fall back to reactive-only
as the reader contract says. `/rate-limit-guard:check` and `/rate-limit-guard:setup check` report
"mods off" in that case. A hook that throws passes its event through unchanged.

## Behavior

- **Atomic, last-writer-wins snapshot.** Concurrent sessions write one path; readers never see torn
  JSON (temp file + rename, with a brief retry for the Windows rename-over-open-target case). The
  helper takes a short lock, refuses an older `captured_at` over a newer one, and keeps a
  windowless body from replacing windows. Last-writer-wins still applies between sessions: a
  session whose last API response is minutes old can write its older reading over a newer one,
  until the next write from a session with a fresher response.
- **Fail-open capability detection.** Sessions whose auth exposes no subscription windows (API-key,
  enterprise) write an honest snapshot without `rate_limits`; consumers treat that as unknown and
  run reactive-only rather than throttling on fabricated data. Cloud / remote sessions typically
  have no file a consumer can read. That is the same unknown → reactive-only classification,
  documented as the expected degraded mode in
  [`reference/reader-contract.md`](reference/reader-contract.md) ("Cloud / remote sessions"), with
  a documented residual that a live cloud producer is out of scope until one exists.
- **An unchanged reading costs no process.** The module compares each reading with the last one it
  wrote and with the `captured_at` on disk, in process, so an unchanged reading inside the 300-second
  floor starts nothing. That floor is half the reader contract's 10-minute staleness budget, so a
  session whose windows sit still refreshes `captured_at` well before a reader could call it stale.
- **Multi-account operation is a narrowed gap.** The snapshot names the account whose windows it
  carries in an `account.email` field, so a machine switching accounts is visible to a reader that
  checks it. Lanes drop a latched pause on an account change: while paused they read
  `.oauthAccount.emailAddress` from `.claude.json` directly and re-evaluate against the new
  account's windows. The gap that remains is attribution: the field is **absent** whenever the
  module could not attribute the observation, which covers an unreadable state file, no
  email-shaped value, and an account that changed between the last API response and the write. A
  lane that cannot attribute keeps its latch. The loop-lane convention §6 owns that framing; the
  reader contract states the absence cases and the untrusted-value rule
  (`reference/reader-contract.md`, "Tee file shape").

## Tests and their budgets

`claude plugin test plugins/rate-limit-guard` runs the module's suite
(`hooks/rate-limit-guard.test.ts`) with stubbed Claude Code calls; `lib/write-snapshot.test.mjs`
covers the helper. The module's process budget, counted in the hook-budget convention's unit (one
process start): **0**
processes on a tool result, prompt, measurement or timer tick that writes nothing, and **1** (the
`node` helper) per write, with writes at most once per changed reading and no more often than every
300 seconds when unchanged. The `budget:` test pins it: 50 unchanged tool results start no process,
and one change starts exactly one.

The tests retired with the statusline tee, and what holds their property now:

| Retired test | Replacement |
|---|---|
| The tee suite: snapshot shape, account, no-change floor, enablement | the `snapshot:`, `account:`, `floor:` and `switch:` tests in `hooks/rate-limit-guard.test.ts` |
| The tee suite: atomic write, windowless preservation, locks | `lib/write-snapshot.test.mjs` |
| The tee suite: the zero-fork render trace | the `budget:` test, at the budget above |
| The bench lanes and their recorded process counts | the `budget:` test, at the budget above |
| The tee suite: transparency, spool and drain, async writes, the disabled marker | none: the plugin no longer wraps a status line or spools |
| The shim and compose-script suites | none: no shim ships; the setup skill's evals cover removing an old one |

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install rate-limit-guard@<marketplace>
```

The module and the StopFailure hook are active once the plugin loads (the next session, or
`/reload-plugins` in an open one); nothing needs wiring.
`/rate-limit-guard:setup check` verifies the result.

## Requirements

- Claude Code 2.1.287 or later, with mods on, for the module. Below that, or with mods off, only
  the StopFailure hook runs.
- [Node.js](https://nodejs.org/en/download) on `PATH`. The `StopFailure` hook launches through
  `node hooks/exec-bash.mjs`, and the module writes the file by running `node`; Claude Code's
  native binary does not ship or use Node. Without it the hook records nothing and the module
  writes nothing, while its lines and band row still work.
- Bash for the StopFailure hook: on native Windows,
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows), which
  `hooks/exec-bash.mjs` finds.
- Claude.ai subscription auth (Pro/Max) for proactive window data. On other auth the guard is
  reactive-only.

`/rate-limit-guard:check` reports whether `node` resolves and whether the module can load,
read-only. It installs nothing.

## Configuration

The `userConfig` options:

| Option | What it controls |
|---|---|
| `rate_limit_guard_enabled` | Kill switch for the StopFailure detection hook **and** the module's snapshot writes (default `true`). It does not stop the module's lines. |
| `rate_limit_lines_enabled` | The module's lines to Claude, and the operator-mode suggestions (default `true`). |
| `rate_limit_report_mode` | `automatic` (default) or `operator`; see [Operator mode](#operator-mode). |
| `rate_limit_line_threshold` | Window use for the threshold line (default `95`). |
| `rate_limit_approach_pct` | Window use for the one approach line (default `90`). |
| `rate_limit_line_data` | What a line carries beside its verdict: `percent`, `window`, `reset` (default `verdict,window,reset`). |
| `rate_limit_guard_band` | The band row (default `false`). |
| `rate_limit_guard_toast` | The toast when a window nears or reaches the threshold or resets (default `true`); the transcript line stays either way. |

A threshold or approach mark outside 1 to 100, or line data with an unknown item, reads as that
option's default with one transcript line naming it; the thresholds declare no range because Claude
Code refuses the whole module for a value outside one. A value of the wrong type (text for a
number, a number for a switch) still stops the module loading.

The module reads its options when it loads. Claude Code reloads a module when its options change,
so a switch turned off takes effect from the next event, with no restart. The StopFailure hook
receives `rate_limit_guard_enabled` as `CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED` at session
start.

- **Pointer**: the doc comment on `Register` in the `claude-code/index.d.ts` types Claude Code
  writes for its build (see
  [create: get the types for your build](https://code.claude.com/docs/en/plugins/mods/create#get-the-types-for-your-build)).
- **As of**: 2026-10-03, Claude Code 2.1.288.
- **Recheck trigger**: that doc comment stops saying an options change reloads the plugin.

Set it with `/plugin configure rate-limit-guard@<marketplace>`, or headless via `claude plugin install
rate-limit-guard@<marketplace> -s <scope> --config rate_limit_guard_enabled=false`, against an
already-installed plugin that prints `already installed` and still writes the value. Never
uninstall to reconfigure: that drops the whole stored `pluginConfigs` entry and resets every
option to its manifest default. The verified-version record lives in the
[plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

The file path and the 95% pause threshold are deliberately **not** configurable: they are contract
constants that cross-plugin consumers inline from the
[reader contract](reference/reader-contract.md); a per-user override would silently split the
writer from its readers. The kill switch stops this plugin's writes and records; turning the
plugin off for a project is `enabledPlugins`, and removing it is uninstall.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `rate_limit_guard_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED` | Turns on the StopFailure detection hook and the module's snapshot writes to the machine-scope rate-limit file. Lines to Claude have their own option. On by default. Read from managed settings first, then user settings. |
| `rate_limit_lines_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_RATE_LIMIT_LINES_ENABLED` | Sends Claude one line when a rate-limit window approaches or reaches the line threshold, when it resets, and after a compaction, a resume or a /clear at the threshold. On by default. |
| `rate_limit_report_mode` | string | `"automatic"` | `CLAUDE_PLUGIN_OPTION_RATE_LIMIT_REPORT_MODE` | automatic (default) sends the lines to Claude; operator holds them in a turn a person typed and offers the person a ready-made prompt and a notice row above the prompt when the turn ends. Headless, loop and schedule turns get automatic lines either way. |
| `rate_limit_line_threshold` | number | `95` | `CLAUDE_PLUGIN_OPTION_RATE_LIMIT_LINE_THRESHOLD` | Window use at which Claude gets the threshold line, 1 to 100; any other value reads as the default. Default 95, the loop lanes' pause edge, which stays 95 whatever this is set to. |
| `rate_limit_approach_pct` | number | `90` | `CLAUDE_PLUGIN_OPTION_RATE_LIMIT_APPROACH_PCT` | Window use at which Claude gets one approach line before the threshold, 1 to 100; any other value reads as the default. Default 90; at or above the threshold, no approach line is sent. |
| `rate_limit_line_data` | string | `"verdict,window,reset"` | `CLAUDE_PLUGIN_OPTION_RATE_LIMIT_LINE_DATA` | Comma list of what a line carries beside its verdict, which every line has: percent, window and reset. Default verdict,window,reset; a list with an unknown item reads as the default. Never the account email or the session name. |
| `rate_limit_guard_band` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_BAND` | Draws the 5-hour and 7-day window figures in a row above the prompt. Off by default. Turn it on in /config, or for one session with /rate-limit-guard band on. |
| `rate_limit_guard_toast` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_TOAST` | Shows a toast and writes one transcript line when a rate-limit window nears or reaches the line threshold, or resets from it. Off keeps the transcript line. On by default. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure rate-limit-guard@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
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

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
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
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## Consumers

Written for Claude in every session that loads the plugin and for the loop-lane convention's three
lanes (work-items `work-loop` and `attend-queue`, source-control `babysit-loop`), which inline the
reader contract's operable floor. Any session or tool on the machine may read the same files under
the same contract.

## License

MIT (SPDX-License-Identifier: MIT).
