# context-guard

A Claude Code plugin that makes each session's context-window usage observable to any session or
tool that needs it, so long-running workflows can route heavy work away from a degraded context
**before** quality slips, instead of guessing. Five parts:

- **Statusline shim** (`scripts/statusline-shim.sh`), the durable wiring target. Installed once to
  `~/.claude/context-guard/bin/`, it resolves whichever tee version is installed at run time, so a
  plugin update never requires re-wiring and an uninstall degrades to your statusline running
  alone. Pure Bash builtins: it adds no measurable time to a refresh.
- **Statusline tee** (`scripts/statusline-tee.sh`), a transparent wrapper around your statusline
  command. Each refresh it atomically writes `captured_at`, `session_id`, and the session's
  `context_window` object (copied verbatim from the statusline stdin) to the per-session path
  `~/.claude/context-guard/context/<session_id>.json`, then passes your statusline through
  byte-for-byte. With no statusline configured it doubles as a minimal standalone statusline.
- **Zone resolver** (`scripts/context-zone.sh`). `context-zone.sh <session_id>` prints exactly one
  word: `smart` / `acceptable` / `dumb` / `unknown`. Two band shapes, combined conservatively (the
  worse computable zone wins): percentage bands over `used_percentage` (shipped defaults
  smart ≤ 50 < acceptable ≤ 75 < dumb) and window-class token bands over occupancy
  (`total_input_tokens + total_output_tokens`; shipped defaults 100k/160k on a 200k window,
  200k/400k on a 1M window). Bands come from the machine-scope
  `~/.claude/context-guard/zones.json` when present and valid, else from the shipped defaults.
  Zones say *where you are*; consumers decide *what to do*.
- **Zone-crossing hooks** (`hooks/`), the first shipped consumer. Once per transition into a
  worse zone, a PostToolBatch/UserPromptSubmit hook reports the crossing (advisory; silent on
  unchanged, improving, or `unknown` zones), **splitting the report by audience**: the
  continuation menu. Continue, `/clear`, handoff-then-`/clear`, `/compact`. Renders to the
  operator on `systemMessage`, because choosing among them is the human's call; the model's
  channel carries the zone determination plus the counter-steer that a zone word is a measurement
  and not a decay signal, and never an exit menu. An exit menu injected into model context
  manufactures the model's own initiative to stop, summarize, or hand off, which the
  instruction-audit catalog flags as check I23. A PostCompact hook writes an
  evidence-degraded marker next to the session's snapshot, and both zone consumers honor it: a
  compacted session's effective zone is dumb regardless of its post-compaction numbers. An
  optional **blocking** mode (`zone_hook_mode` userConfig) adds a PreToolUse gate that denies new
  Write/Edit/NotebookEdit/Agent/Workflow calls on a fresh dumb-zone snapshot past a grace budget, fail-open on `unknown`, with handoff-path writes, reads, Bash, and Skill invocations never
  gated, so a durable handoff is always writable.
- **Reader contract** (`reference/reader-contract.md`), the authoritative consumer contract: the
  snapshot path pattern, file shape, the 10-minute staleness rule, fail-open capability detection,
  the zones.json shape, session-id discovery via `${CLAUDE_SESSION_ID}`, and the
  zone-is-not-a-compaction-indicator rule. Its companion
  `reference/cloud-headless-capture.md` is the writer-side channel inventory: why the statusline is
  the only capture channel, which other channels were checked and rejected (with sources and
  dates), including the two that do carry live occupancy and still cannot supply a snapshot, and
  why `unknown` in a session that runs no statusline, a cloud or headless session by default, is
  structural rather than a defect.

## Behavior

- **Transparent by contract.** No tee outcome. Missing `jq`, unwritable path, a rename blocked by
  a concurrent reader. Ever changes the wrapped statusline's output or exit code. Missing `jq` is
  surfaced as a visible one-line notice, never a silent skip.
- **Per-session, atomic snapshots.** One file per session id (no cross-session last-writer-wins);
  readers never see torn JSON (temp file + rename, with a brief retry for the Windows
  rename-over-open-target case). Stale sibling files are pruned on write with a 14-day cutoff, far above the staleness window, so live-but-idle sessions always survive.
- **Path containment.** `session_id` becomes a filename, so the tee accepts only `[A-Za-z0-9_-]`
  and skips the snapshot for anything else, the wrapped statusline is unaffected.
- **Fail-open zone resolution.** Absent, stale, or unparsable snapshots, null or out-of-range
  `used_percentage`, null `current_usage` (early-session and post-`/compact` statusline states),
  a non-ISO `captured_at`, a snapshot whose embedded `session_id` differs from the requested one,
  or missing `jq` all resolve `unknown`. Consumers take their conservative path on data they
  cannot trust, never a fabricated zone. The shipped bands are declared judgment defaults: no
  official auto-compaction threshold is documented (verified 2026-07-24); `zones.json` is the
  tuning path. The trigger itself is operator-tunable even though its default is unpublished: `autoCompactWindow`, `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, and
  `autoCompactEnabled` / `DISABLE_AUTO_COMPACT`, and bands belong **below** whatever it resolves
  to, normalized into the percentage shape, so the session reaches a boundary decision before the
  harness compacts for it. Note that `used_percentage` always measures against the model's *full*
  window, so a lowered auto-compact window no longer shows up in the percentage. The reader
  contract owns those surfaces, their verification dates, and the rationale.
- **Integrity boundary (stated honestly).** The snapshot directory is owner-only where POSIX
  modes work; on Windows ACL volumes the `chmod` is a no-op and other local users could forge
  snapshots. Zones are routing hints. Consumers must never attach security or egress decisions
  to a zone word. See the reader contract's untrusted-data section.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install context-guard@<marketplace>
```

The tee needs two operator steps, both one-time:

1. `/context-guard:setup apply`. Installs the statusline shim to
   `~/.claude/context-guard/bin/statusline-shim.sh` (and seeds/refreshes `zones.json`). The shim is
   inert until step 2.
2. `/context-guard:setup check`. Verifies prerequisites and prints the exact `settings.json`
   statusline edit (wrapping your existing command, or standalone) for you to apply. The plugin
   never edits your settings itself.

You wire the **shim**, not the tee, and that wiring is permanent: `${CLAUDE_PLUGIN_ROOT}` is
version-pinned and the old version directory is pruned ~14 days after an update, so a statusline
wired straight to `<plugin-root>/scripts/statusline-tee.sh` silently stops teeing on the next
version bump and then takes the whole statusline down when the path disappears. The shim resolves
the newest installed tee at run time, so plugin updates need no re-wiring, and it passes your
statusline through unchanged when no tee is installed (including after uninstall). `check` still
flags legacy version-pinned wiring if you have it.

## Requirements

The scripts run on Bash (Git Bash on native Windows. Install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows); the statusline wiring
invokes `bash` explicitly) and need [`jq`](https://jqlang.org/download/) on `PATH` for the tee, the
zone resolver, and the standalone statusline. The snapshot updates only while an interactive
session refreshes the statusline; `context_window` fields can be `null` early in a session and
right after `/compact`, per the
[statusline reference](https://code.claude.com/docs/en/statusline). Readers own null handling.

Cost: the tee adds roughly 0.6–0.9 s per statusline refresh on Windows/Git Bash (process-spawn
bound. `jq` and `date`), and correspondingly less on native POSIX shells. The statusline is not on
the input path, so this is display latency, not typing latency; `refreshInterval` in your settings
governs how often it runs.

## Configuration

Three `userConfig` options, all hook-scoped: `context_guard_hooks_enabled` (kill switch, default
true), `zone_hook_mode` (`advisory` default | `blocking`), and `zone_gate_grace_calls` (blocking
mode's grace budget, in-script default 20). The snapshot path and the 10-minute staleness rule are
deliberately **not** configurable: they are contract constants that cross-plugin consumers inline
from the [reader contract](reference/reader-contract.md); a per-user override would silently split
the writer from its readers. Band numbers are the one tunable. Via
`~/.claude/context-guard/zones.json` (shape in the reader contract), which the operator's own
statusline display may read too, so display and consumers never drift. Disabling the tee is the
operator's edit (remove or unwrap the statusline command); disabling everything is
`enabledPlugins` / uninstall.

## Consumers

The plugin's own zone-crossing hooks are the first shipped consumer. Next: the `plugin-quality`
audit skill (zone-informed dispatch and evidence-flush decisions, conservative on `unknown`). Any
session or tool on the machine may read the same files under the same contract.

<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->
<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `context_guard_hooks_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_CONTEXT_GUARD_HOOKS_ENABLED` | Master switch for the zone-crossing injection, blocking gate, and PostCompact marker hooks |
| `zone_hook_mode` | string | `"advisory"` | `CLAUDE_PLUGIN_OPTION_ZONE_HOOK_MODE` | advisory (default) injects guidance only; blocking additionally denies new Write/Edit/NotebookEdit/Agent/Workflow calls on a fresh dumb-zone snapshot past the grace budget (fail-open on unknown; handoff-path writes, reads, Bash, and Skill stay allowed) |
| `zone_gate_grace_calls` | string | `"20"` | `CLAUDE_PLUGIN_OPTION_ZONE_GATE_GRACE_CALLS` | Blocking mode only: number of matched tool calls allowed after the session first resolves dumb before the gate denies (in-script default 20) |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure context-guard@<marketplace>`.
2. **Headless** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install context-guard@<marketplace> -s <scope> --config context_guard_hooks_enabled=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value — verified on Claude Code 2.1.240,
   for a non-sensitive option at `user` scope, by writing a non-default value to an
   installed plugin and restoring it. The short-circuit message is about the install,
   not the config write. That has not been verified for a `sensitive` option or for
   `project`/`local` scope. Do **not** `claude plugin uninstall` in order to
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
       "context-guard@<marketplace>": {
         "options": {
           "context_guard_hooks_enabled": <value>
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

## License

MIT (SPDX-License-Identifier: MIT).
