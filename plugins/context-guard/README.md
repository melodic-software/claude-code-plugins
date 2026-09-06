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
  continuation menu (continue, `/clear`, handoff-then-`/clear`, `/compact`) renders to the
  operator on `systemMessage`, because choosing among them is the human's call; the model's
  channel carries the zone determination plus the counter-steer that a zone word is a measurement
  and not a decay signal, and never an exit menu. An exit menu injected into model context
  manufactures the model's own initiative to stop, summarize, or hand off, which the
  instruction-audit catalog flags as check I23. A PostCompact hook writes an
  evidence-degraded marker next to the session's snapshot, and both zone consumers honor it: a
  compacted session's effective zone is dumb regardless of its post-compaction numbers. An
  optional **blocking** mode (`zone_hook_mode` userConfig) adds a PreToolUse gate that denies new
  Write/Edit/NotebookEdit/Agent/Workflow calls on a fresh dumb-zone snapshot past a grace budget, fail-open on `unknown`, with handoff-path writes, reads, Bash, and Skill invocations never
  gated, so a durable handoff is always writable. All four hook rows, including the two advisory
  `zone-crossing-inject.sh` rows (PostToolBatch and UserPromptSubmit), carry a 60-second timeout.
  The 0.4.8 measurement sized that cap: on Windows 11 / Git Bash with Defender real-time protection
  enabled, `zone-crossing-inject.sh` reached 22.0 s on a small payload. A timeout only caps a hook
  that has already stalled and saves nothing on a normal fire, so a lower cap would not speed up
  the prompt path; on that profile it would cancel the advisory on essentially every fire rather
  than only on a stuck one. The rows stay at 60 until a re-measurement on that profile shows
  headroom. A hook blocked on stdin is bounded separately by `cg::read_payload` in
  `hooks/payload.sh`, which reads to EOF under a 5-second `read -t` and which both rows use.
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

- **Transparent by contract.** No tee outcome (missing `jq`, unwritable path, or a rename blocked
  by a concurrent reader) ever changes the wrapped statusline's output or exit code. Missing `jq` is
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
  `autoCompactEnabled` / `DISABLE_AUTO_COMPACT`. Bands belong **below** whatever it resolves
  to, normalized into the percentage shape, so the session reaches a boundary decision before the
  harness compacts for it. Note that `used_percentage` always measures against the model's *full*
  window, so a lowered auto-compact window no longer shows up in the percentage. The reader
  contract owns those surfaces, their verification dates, and the rationale.
- **Integrity boundary (stated honestly).** The snapshot directory is owner-only where POSIX
  modes work; on Windows ACL volumes the `chmod` is a no-op and other local users could forge
  snapshots. Zones are routing hints. Consumers must never attach security or egress decisions
  to a zone word. See the reader contract's untrusted-data section.

### Hook cost accounting

`zone-crossing-inject.sh` runs on PostToolBatch, which fires once per tool batch, so every process
it starts is paid on the critical path of every batch. Measured 2026-09-02 on Windows 11 under Git
Bash: 12 trials per row, each preceded by a `bash -c :` spawn floor so the floor and the hook see
the same machine load, medians reported. Cost is given in spawn-equivalents (hook wall time divided
by that run's floor) because the absolute figure moves with load: the measured floor ranged 36 to
94 ms across the before rows and 46 to 56 ms across the after rows, against a 33 ms program
baseline. Process counts are of commands in command position in the hook process, so a shell
builtin such as `command -v jq` is correctly not counted.

Counts below are processes started by the hook itself. The zone resolver is one of them, and it
starts its own; the whole-fire total is in the paragraph after the table.

| Path | Processes before | Processes after | Spawn-equivalents before | After |
|---|---|---|---|---|
| PostToolBatch, steady zone (the common case) | 11 | 2 | 18.9 | 10.8 |
| PostToolBatch, no snapshot yet | 6 | 2 | 8.6 | 4.8 |
| PostToolBatch, crossing into a worse zone | 11 | 2 | 16.5 | 11.8 |
| UserPromptSubmit, steady zone | 11 | 2 | 18.4 | 11.8 |
| PreToolUse gate, default advisory posture | 2 | 0 | 2.5 | 1.4 |
| PostCompact marker | 9 | 4 | 9.4 | 5.7 |

`scripts/context-zone.sh`, the band authority the hooks call once per resolve, was cut in the same
pass. It spent six processes: one `jq` for the snapshot, two `date` for the staleness arithmetic,
and three `awk` for the two band comparisons and the version gate. It now spends one, and a second
only when a `zones.json` override is present. The band resolution moved ahead of the snapshot pass
so the resolved bands are handed to that one `jq` as data, and the two `zones.json` passes became
one over the same file. Measured with old and new interleaved in a single loop against the same
floor, so machine load cannot skew the comparison:

| Resolver, realistic snapshot | Processes | Spawn-equivalents |
|---|---|---|
| Before | 6 | 9.5 |
| After | 1 | 2.3 |

Whole steady PostToolBatch fire, end to end: 15 processes before this pass (17 when the snapshot
carries the token fields), 3 after. Those three are one `jq` in the hook, the resolver's own
process, and one `jq` inside it.

What went: every `dirname` call, replaced by parameter expansion (three in the zone-crossing hook,
two in each of the others); a second `jq`, by reading both envelope fields in one pass;
`tr -cd | head -c` on each of the two state markers, by `$(<file)` plus parameter expansion; and
`mkdir` and `rm` calls that the steady path had already made unnecessary, behind existence guards.
`date -u` in the PostCompact marker became printf's `%()T` format under a `TZ=UTC` prefix, verified
to produce the same string on a host whose local zone is not UTC, so the trailing `Z` stays honest.
`%()T` arrived in bash 4.2, so on an older shell (stock macOS 3.2) that site and the resolver's
clock fall back to the exact `date` invocation they replaced; the counts above are for 4.2 and
later, where the fallback is never reached.
No decision, no emitted text and no state file changed: an eleven-scenario capture covering
both events, both crossing directions, hostile and absent session ids and an empty payload diffs
byte-identical on stdout, exit code and every state file, and the contract tests assert the
remaining process budget by trace so a regression fails a test rather than slowing a session.

The resolver's own equivalence was proven the same way, at more depth, because its rewrite moved
security-relevant gates. A differential harness runs the old and new resolver over 103 inputs and
compares stdout, stderr and exit code byte for byte: both band shapes at every boundary, the
window-class selection, the plausibility guard, the version gate either side of 2.1.132, the
combination rule, the staleness window either side, the whole calendar-invalid `captured_at` class,
all four trust gates, and every `zones.json` variant including both malformed-notice paths. Zero
differences, stable across three runs.

One subtlety is worth stating, because it would have been a silent widening. jq's
`fromdateiso8601` is not `date -u -d`: it NORMALIZES a structurally well-formed but
calendar-invalid timestamp rather than refusing it, so February 30th would have become March 2nd
and second 60 would have rolled into the next minute. The strict ISO-8601 format test exists to
stop a lenient parser accepting a forged `captured_at`, and normalizing there would have undone it.
The parsed epoch is therefore formatted back and required to equal the input byte for byte, which
restores `date`'s answer on every such value.

What stays, and why: one `jq` pass in the hook, because a PostToolBatch payload carries every
serialized tool result, so a regex for the envelope fields would be matching against tool output;
one `jq` in the resolver, carrying every gate and both comparisons; and the resolver's own process.
Running it rather than sourcing it is deliberate: it is a documented seam that `zone-gate.sh` and
its test suite invoke as an executable, and it signals through `exit`. Making it sourceable would
change a public interface to save one process, and that is the only structural cut left here.

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

The scripts run on Bash (Git Bash on native Windows, so install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows); the statusline wiring
invokes `bash` explicitly) and need [`jq`](https://jqlang.org/download/) on `PATH` for the tee, the
zone resolver, and the standalone statusline. The snapshot updates only while an interactive
session refreshes the statusline; `context_window` fields can be `null` early in a session and
right after `/compact`, per the
[statusline reference](https://code.claude.com/docs/en/statusline). Readers own null handling.

Cost: the tee adds roughly 0.6–0.9 s per statusline refresh on Windows under Git Bash, where the
cost is process-spawn bound on `jq` and `date`, and correspondingly less on native POSIX shells. The statusline is not on
the input path, so this is display latency, not typing latency; `refreshInterval` in your settings
governs how often it runs.

### Hook budget accounting

Per [`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md),
the PostToolBatch and UserPromptSubmit rows are per-turn hooks and the PreToolUse row is
per-tool-call, all always-on. Measured on Windows 11 under Git Bash, twelve trials against an
interleaved `bash -c :` floor, old and new interleaved in one loop (2026-09-02):

| Event | Fires | Spawn-equivalents | What changed |
| --- | --- | --- | --- |
| PostToolBatch, steady zone (`zone-crossing-inject.sh`) | 1 | 18.9 before, 10.8 after (0.7.34) | 11 processes to 2: one `jq` reading both payload fields, `dirname` and `tr` pipelines replaced by expansions, `mkdir -p` behind a `-d` guard |
| UserPromptSubmit, steady zone (the same `zone-crossing-inject.sh`) | 1 | 18.4 before, 11.8 after (0.7.34) | same script, same cuts; measured separately because the payload differs |
| PreToolUse `Write`/`Edit`, advisory mode (`zone-gate.sh`) | 1 | 2.5 before, 1.4 after (0.7.34) | no process spawned in the default posture |
| PostCompact (`post-compact-mark.sh`) | 1 | 9.4 before, 5.7 after (0.7.34) | 9 processes to 4: `date` replaced by printf's clock with a `date` fallback; `mkdir` and `rm` behind existence guards |
| Zone resolver (`scripts/context-zone.sh`, called by the rows above) | per resolve | 9.5 before, 2.3 after (0.7.34) | six processes to one `jq`; a whole steady PostToolBatch fire is 3 processes, down from 15 |

**0.7.45, advisory `zone-gate.sh` sources nothing.** 2026-09-06, Linux CI host.
The default `zone_hook_mode` is advisory, so the gate is inert. It still parsed
`hook-utils.sh` (and `payload.sh`) to discover that. The MODE check now sits
above every `source`, the same shape as the kill-switch hoist. Spawn census
stays at 0 PATH-visible execs; `bash -x` sources of `hook-utils.sh` go 1 → 0.
Wall clock, n=20 after 2 warmup, host `spawn_probe` measurable (min 0.5 ms,
spread 1.78×): p50 4.8 → 1.4 ms, p95 5.0 → 1.5 ms. Blocking mode still sources
the library after the MODE check and is unchanged.

The two advisory rows keep their 60-second timeout: the 0.4.8 measurement put this script at
22.0 s on Windows with Defender real-time protection, and a timeout caps a stalled hook without
speeding a normal one.

## Configuration

Three `userConfig` options, all hook-scoped: `context_guard_hooks_enabled` (kill switch, default
true), `zone_hook_mode` (`advisory` default | `blocking`), and `zone_gate_grace_calls` (blocking
mode's grace budget, in-script default 20). The snapshot path and the 10-minute staleness rule are
deliberately **not** configurable: they are contract constants that cross-plugin consumers inline
from the [reader contract](reference/reader-contract.md); a per-user override would silently split
the writer from its readers. Band numbers are the one tunable, via
`~/.claude/context-guard/zones.json` (shape in the reader contract), which the operator's own
statusline display may read too, so display and consumers never drift. Disabling the tee is the
operator's edit (remove or unwrap the statusline command); disabling everything is
`enabledPlugins` / uninstall.

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

## Consumers

The plugin's own zone-crossing hooks are the first shipped consumer. Next: the `plugin-quality`
audit skill (zone-informed dispatch and evidence-flush decisions, conservative on `unknown`). Any
session or tool on the machine may read the same files under the same contract.

## License

MIT (SPDX-License-Identifier: MIT).
