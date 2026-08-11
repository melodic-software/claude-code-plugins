# rate-limit-guard

A Claude Code plugin that makes the machine's shared subscription rate-limit windows observable to
every session that needs them — so autonomous loop lanes can pause **before** hitting a limit and
resume on their own after the reset. Four parts:

- **Statusline shim** (`scripts/statusline-shim.sh`) — the durable wiring target. Installed once to
  `~/.claude/rate-limit-guard/bin/`, it resolves whichever tee version is installed at run time, so
  a plugin update never requires re-wiring and an uninstall degrades to your statusline running
  alone. Pure Bash builtins: it adds no measurable time to a refresh.
- **Statusline tee** (`scripts/statusline-tee.sh`) — a transparent wrapper around your statusline
  command. Each refresh it atomically writes the session's `rate_limits` (both the 5-hour and
  7-day windows), a `captured_at` timestamp, and the session-distinguishing fields to the fixed
  machine-scope contract path `~/.claude/rate-limit-guard/rate-limits.json`, then passes your
  statusline through byte-for-byte. With no statusline configured it doubles as a minimal
  standalone statusline.
- **StopFailure hook** (`hooks/record-rate-limit-stop.sh`) — the reactive fallback. When a turn
  ends on a rate-limit API error, it appends a detection record to
  `~/.claude/rate-limit-guard/stop-events.jsonl`. StopFailure output and exit codes are ignored by
  the harness, so the hook is side-effect-only by design.
- **Reader contract** (`reference/reader-contract.md`) — the authoritative consumer contract: the
  fixed tee path, the 90%-of-either-window pause threshold, the staleness rule, pause-end
  semantics, capability-detect fail-open, and drain-then-pause.

## Behavior

- **Transparent by contract.** No tee outcome — missing `jq`, unwritable path, a rename blocked by
  a concurrent reader — ever changes the wrapped statusline's output or exit code. Missing `jq` is
  surfaced as a visible one-line notice, never a silent skip.
- **Atomic, last-writer-wins snapshot.** Concurrent sessions write one path; readers never see torn
  JSON (temp file + rename, with a brief retry for the Windows rename-over-open-target case).
- **Fail-open capability detection.** Sessions whose auth exposes no `rate_limits` (API-key,
  enterprise) tee an honest snapshot without the key; consumers treat that as unknown and run
  reactive-only rather than throttling on fabricated data.
- **Multi-account operation is a known gap, not a supported mode.** The snapshot carries no account
  identifier (none exists in the statusline schema today), so a machine switching accounts mid-drain
  feeds wrong windows to running lanes and the guard cannot detect it. The loop-lane convention §6
  owns that framing; the reader contract cites it. The wrapper adopts a future account-identifying
  field automatically only when its own top-level key name contains `account`; every other shape
  needs a writer change (`reference/reader-contract.md`, "Tee file shape").

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install rate-limit-guard@melodic-software
```

The StopFailure hook is active immediately. The statusline tee needs two operator steps, both
one-time:

1. `/rate-limit-guard:setup apply` — installs the statusline shim to
   `~/.claude/rate-limit-guard/bin/statusline-shim.sh`. The shim is inert until step 2.
2. `/rate-limit-guard:setup check` — verifies prerequisites and prints the exact `settings.json`
   statusline edit (wrapping your existing command, or standalone) for you to apply. The plugin
   never edits your settings itself.

You wire the **shim**, not the tee, and that wiring is permanent: `${CLAUDE_PLUGIN_ROOT}` is
version-pinned and the old version directory is pruned ~14 days after an update, so a statusline
wired straight to `<plugin-root>/scripts/statusline-tee.sh` silently stops teeing on the next
version bump and then takes the whole statusline down when the path disappears. The shim resolves
the newest installed tee at run time, so plugin updates need no re-wiring, and it passes your
statusline through unchanged when no tee is installed (including after uninstall).

Running alongside `context-guard`? The tees are transparent wrappers, so they nest — each through
its own shim, with the innermost command still owning stdout and the exit code. Both setup skills
print that combined form.

## Requirements

The scripts run on Bash (Git Bash on native Windows — install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows); the statusline wiring
invokes `bash` explicitly) and need [`jq`](https://jqlang.org/download/) on `PATH` for the tee and
the standalone statusline. Proactive window data requires Claude.ai subscription auth (Pro/Max) —
`rate_limits` appears only there, per the
[statusline reference](https://code.claude.com/docs/en/statusline); on other auth the guard is
reactive-only. The tee updates only while an interactive session refreshes the statusline.

Cost: the tee adds roughly 0.6–0.9 s per statusline refresh on Windows/Git Bash (process-spawn
bound — `jq` and `date`), and correspondingly less on native POSIX shells. The statusline is not on
the input path, so this is display latency, not typing latency; `refreshInterval` in your settings
governs how often it runs.

## Configuration

One `userConfig` option:

| Option | What it controls |
|---|---|
| `rate_limit_guard_enabled` | Kill switch for the StopFailure detection hook (default `true`). |

Set it with `/plugin configure rate-limit-guard`, or headless on a fresh install via
`claude plugin install rate-limit-guard@<marketplace> --config rate_limit_guard_enabled=false`.

The tee path and the 90% pause threshold are deliberately **not** configurable: they are contract
constants that cross-plugin consumers inline from the
[reader contract](reference/reader-contract.md); a per-user override would silently split the
writer from its readers. Disabling the statusline tee is the operator's edit (remove or unwrap the
statusline command); disabling the hook is the kill switch; disabling everything is
`enabledPlugins` / uninstall.

## Consumers

Written for the loop-lane convention's three lanes (work-items `work-loop` and `attend-queue`,
source-control `babysit-loop`), which inline the reader contract's operable floor. Any session or
tool on the machine may read the same files under the same contract.

<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `rate_limit_guard_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_RATE_LIMIT_GUARD_ENABLED` | Master switch for the StopFailure detection hook |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure rate-limit-guard`.
2. **Headless, at install time** — repeat `--config` for each option:

   ```shell
   claude plugin install rate-limit-guard@melodic-software --config rate_limit_guard_enabled=<value>
   ```

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "rate-limit-guard@melodic-software": {
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
- [Plugin settings](https://code.claude.com/docs/en/settings#plugin-settings) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Configuration scopes](https://code.claude.com/docs/en/settings#configuration-scopes) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
