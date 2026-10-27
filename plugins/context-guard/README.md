# context-guard

A Claude Code plugin that makes each session's context-window usage observable to Claude itself and
to any session or tool that needs it, so long-running workflows can route heavy work away from a
degraded context **before** quality slips, instead of guessing. Four parts:

- **The module** (`hooks/register.tsx`), a mod: a hooks module Claude Code runs in its own process.
  It shows the person a toast when the session crosses into a worse context zone, tells Claude the
  same when the operator turns on `model_notices` (off by default), answers `/context-guard` and the
  `mcp__context-guard__status` tool, draws an optional band row, and writes the snapshot file. It
  needs a Claude Code build that can run mods; older builds are unsupported. **Pointer**: when
  deciding which build that is, fetch
  [mods overview: turn mods on or off](https://code.claude.com/docs/en/plugins/mods/overview#turn-mods-on-or-off)
  live. **As of**: 2026-10-11. **Recheck trigger**: the terminal version that section names for
  mods changes. See [The module](#the-module).
- **Zone resolver** (`scripts/context-zone.sh`). `context-zone.sh <session_id>` prints exactly one
  word: `smart` / `acceptable` / `dumb` / `unknown`. Two band shapes, combined conservatively (the
  worse computable zone wins): percentage bands over `used_percentage` (shipped defaults
  smart ≤ 50 < acceptable ≤ 75 < dumb) and window-class token bands over occupancy
  (`total_input_tokens + total_output_tokens`; shipped defaults 100k/150k on a 200k window,
  128k/500k on a 1M window). Bands come from the machine-scope
  `~/.claude/context-guard/zones.json` when present and valid, else from the shipped defaults.
  Zones say *where you are*; consumers decide *what to do*.
- **PostCompact marker hook** (`hooks/post-compact-mark.sh`), a settings hook, so it runs where
  mods are off: it writes an evidence-degraded marker next to the session's snapshot, and the
  module honors it: a compacted session's effective zone is dumb regardless of its
  post-compaction numbers. Its row carries a 60-second timeout. The module is the only source of
  zone lines. No part of the plugin denies a tool call.
- **Reader contract** (`reference/reader-contract.md`), the authoritative consumer contract: the
  snapshot path pattern, file shape, the 10-minute staleness rule, fail-open capability detection,
  the zones.json shape, session-id discovery via `${CLAUDE_SESSION_ID}`, and the
  zone-is-not-a-compaction-indicator rule. Its companion
  `reference/cloud-headless-capture.md` is the writer-side channel inventory: why the module is the
  capture channel, which other channels were checked and rejected (with sources and dates),
  including the two that do carry live occupancy and still cannot supply a snapshot, and why
  `unknown` in a session where the module does not run is structural rather than a defect.

This plugin answers "how full is my context and what happens as it fills". For "what is my context
made of" (the startup measurement and the live per-category breakdown), see the `context-budget`
plugin.

## The module

The module decides from the live session's figures in interactive, `-p`, `--bg` and `/loop`
sessions alike, through a TypeScript copy of the resolver's band function over the same bands; a
shared fixture (`scripts/context-zone.fixtures.mjs`) holds the two resolvers to the same answer.
Tested with `claude plugin test` on Claude Code 2.1.288, and in live runs on 2.1.288: interactive,
`-p`, `--bg` and `/loop` sessions, `/compact`, `/branch` and `--resume` on Linux, and `-p` on
native Windows. The maintainer reviewed and accepted each place those runs differed from the
retired statusline tee, such as an idle session's snapshot going stale where the tee kept
rewriting it. No run was made in the Desktop app, VS Code, a cloud session, or under an
organization's sign-in.

### Lines to Claude

Lines go to Claude only with `model_notices` set to `true`; it is off by default, and then nothing
from this plugin enters Claude's context. Claude can still read the zone from the status tool, and
the person still gets the toast and transcript line below. With it on, a line goes to Claude only at
a boundary, appended to the context of a main-thread tool result or of a prompt; a crossing seen
when a turn ends reaches Claude with the next prompt. With the other options and `zones.json` at
their defaults:

| When | Line |
|---|---|
| The session first reaches a worse zone this cycle | once per zone, "acceptable zone (2 of 3)." |
| The session comes within `approach_margin` points (5) of a zone edge or a `zones.json` threshold; where a token band edge decides the crossing, within that many points of the window in tokens | once per boundary, "acceptable zone (2 of 3), nearing dumb." |
| The session passes a `zones.json` threshold | once per threshold, "past an operator threshold", with the threshold's action |
| After a compaction (not the precompute kind), and after `/resume` or `/branch` | the verdict, once, only when it is past `smart`; after a compaction it is `dumb zone (3 of 3, compacted)` once figures arrive, and until then a session with no figures gets "the context reading is unavailable after the compaction, until the next API response." |
| When the module loads into a session that already has turns (a `--resume` launch, a reload after an options change, a hooks-worker restart) | the verdict, once, only when it is past `smart` |
| After `/clear` | nothing: the new session starts in `smart` and a fresh cycle |

A dip below a boundary sends nothing and starts no new cycle; only a return to `smart` does. An
`unknown` reading sends nothing and changes nothing. Every line carries only the verdict: the zone
word and its rank of three. Past `smart`, the verdict lines at a carrier are followed by one options
line:

```text
context-guard: options: record decisions and pending items in a durable file, then continue, /compact, or hand off with /session-flow:handoff, as you and the user choose. A zone never calls for terser output, fewer agents, or lower quality.
```

The verdict alone pushed Claude toward handoffs and terse delegation
([#7118](https://github.com/melodic-software/claude-code-plugins/issues/7118)), so the line names the
step that keeps state durable and leaves the rest to Claude and the user. A crossing or restatement inside the
approach margin of the next zone adds ", nearing <zone>", and an approach line that would repeat
it is not sent. Lines due at
one carrier: a crossing or restatement recorded before a pending restatement merges into it; a
crossing recorded after it is the newer verdict and replaces it. `zone_line_data` adds figures (percent, tokens,
window); by default a line carries none, and it never carries a session id. A configured action's sentence
(`zones.json` `actions` and `thresholds`, see the [reader contract](reference/reader-contract.md))
appears at its crossing, never before. Subagents get no line. Each line sent to Claude is also written as sent to the debug log
(`claude --debug`).

At a crossing the person gets the continuation menu (continue, `/compact`, `/clear`,
`/session-flow:handoff` then `/clear`) as a 4-second toast, such as
`smart → acceptable · continue, /compact, /clear or handoff`, and one transcript line Claude does
not read, ending `more: /context-guard`. `context_guard_toast` turns the toast off; the transcript
line stays. Both come right after the response, tool call, prompt or status read (`/context-guard`
or the status tool) that showed the crossing, even when Claude's line waits for the next prompt. A
turn [operator mode](#operator-mode) holds gets neither, and neither does a session whose first
reading is already past `smart`, which gets only Claude's line. A crossing already shown in an
unattended turn is not offered again in the next typed turn; Claude gets it at that turn's first
carrier. On every surface but the terminal (the Desktop app, VS Code, mobile), where a toast may not
show, the line is also drawn as one notice row above the prompt until the next typed prompt.
`/context-guard` writes the route through `/session-flow:workflow` and
[When your context fills up](https://code.claude.com/docs/en/context-window#when-your-context-fills-up)
as a transcript line Claude does not read.
The menu never reaches Claude: an exit menu in model context manufactures the model's own
initiative to stop, summarize, or hand off, which the instruction-audit catalog flags as check I23.
Claude's options line lists compaction and a handoff as choices beside continuing, never as a
step to take; it is a deliberate exception to I23, decided by the owner in #7118.

### Operator mode

With `zone_report_mode` set to `operator`, a turn a person started by typing (or through the
Remote Control bridge) gets no line. When that turn ends, the line is offered as the prompt box's
suggestion (Tab takes it) and shown as one notice row above the prompt, on every surface and never
as a toast; with text in the box, only the notice shows, and the suggestion is offered again once
the box is empty. Where nobody can take a
suggestion, the line goes to Claude as in automatic mode: `-p` and SDK turns, `/loop` and scheduled
turns, task notifications, a session with no drawing surface, and a suggestion the session reports
it cannot show. A suggestion that was shown but not taken goes to Claude as the ordinary line at
the next turn no person started (a `--bg` launch turn reads as typed, so its suggestion can go
unseen); the next typed turn instead drops it unsent. Claude Code offers no way to withdraw a
shown suggestion, so it stays in the box after that hand-off.

Which apps draw the band's site, `AbovePrompt`, is upstream's render-sites table to say. No probe
of this plugin ran in the Desktop app or VS Code.

- **Pointer**: [mods reference: render sites](https://code.claude.com/docs/en/plugins/mods/reference#render-sites).
- **As of**: 2026-10-03, Claude Code 2.1.288.
- **Recheck trigger**: the `AbovePrompt` row changes the apps it lists, or a Desktop run of this
  plugin is made.

### The command, the band row and the status tool

`/context-guard` with no argument prints the verdict with its figures, the percent bands beside the
token bands of the session's window class (the worse of the two decides the zone), approach margin,
the band and toast state, and where `zones.json` lives and whether it is present.
Claude reads that reply, as it reads any command's output, so the continuation route and this
README's link go to a separate transcript line Claude does not read. `/context-guard band on` and `band off` set the band row for
the session, and a bare `band` toggles it. The band row is off by default; `context_guard_band`
turns it on. It shows `context-guard: <zone> <n>%` above the prompt, the zone first so a cut row still
shows it, and `context-guard: -` before the first response. Claude can
call `mcp__context-guard__status` for the exact figures from the last API response, the zone,
whether a compaction degraded the evidence, and the bands. Where the session
refuses the tool's registration (an organization policy can refuse a user mod's tools), the module
logs one debug line saying so, and the lines, band and writes carry on.

### Prompt-cache status-line segment (optional)

The main conversation's prompt-cache state reaches only a status line: a mod's
`$.session.usage()` carries no cache expiry, so the band row cannot show it without guessing the
lifetime, which depends on plan and usage-credit state a mod cannot read. `scripts/cache-line.mjs`
reads the status line's `prompt_cache` object and prints one segment:

```text
cache ● warm until 14:32 (1h) · hit 91%
cache ○ cold · next message re-caches ~82k · hit 88% · misses 2 (last: tools_changed)
```

It shows the expiry as a clock time, not a countdown, because Claude Code re-runs the status line
when a warm cache expires; no `refreshInterval` is needed. It prints nothing before the first
response, covers the main conversation only (subagents and workflows have their own, shorter
lifetime the object leaves out), and does not appear in cloud or `-p` sessions, where a status line
does not run. `NO_COLOR` turns its color off. A plugin cannot add a status-line segment, so
`/context-guard:setup apply cache-line` copies the script to `~/.claude/context-guard/cache-line.mjs`
and prints the `statusLine` edit for you to paste, built by the script's `--wire` mode: your existing
command runs first through `--after`, and your other `statusLine` keys stay. It never writes your settings. Pointer: for the
object's fields, see
[Prompt cache fields](https://code.claude.com/docs/en/statusline#prompt-cache-fields). As of:
2026-10-10. Recheck trigger: that section renames a field the script reads.

The plugin sends no keep-warm requests: each one spends usage to save a rebuild that may never
come. For the lifetime rules and the settings that change them, see
[Prompt caching](https://code.claude.com/docs/en/prompt-caching).

### Telemetry

With `HOOK_TELEMETRY_SINK` set, the module sends envelopes per the
[hook-telemetry convention](../../docs/conventions/hook-telemetry/README.md) to the sink,
fire-and-forget, and only on fires that act:

- `zone-crossing-inject`, status `ok`, for each fire that sends lines, with `hook_event`
  `tool.call` or `prompt.submit` and data `zone`, `previous`, `armed` and `injected: true`; and for
  each operator-mode suggestion shown, with `hook_event` `turn.complete` and data `zone`,
  `previous`, `armed`, `injected: false` and `suggested: true`.

A fire that sends nothing emits nothing, and no record carries a `path` field. A relative sink path
is joined onto the session's project root. Unset, nothing is sent.

### Snapshot writes

The module writes `~/.claude/context-guard/context/<session_id>.json` in the
[reader contract](reference/reader-contract.md)'s shape through `lib/write-snapshot.mjs`, run with
`node`, which replaces it atomically, keeps the file and directory owner-only on POSIX, and at most
hourly prunes files older than 14 days. A changed body is written at once; an unchanged one at most
once per 60 seconds. Writes happen after every tool call, at each measurement after a response,
from a 15-second timer that runs only while a turn runs, and at the session's end; an idle session
writes nothing, so its file goes stale after 10 minutes. They follow the plugin's on/off switch
only: `context_guard_hooks_enabled` and `model_notices` do not stop them, and a project that
disables the plugin in `enabledPlugins` gets no snapshot or lines in its sessions. A session
id outside `[A-Za-z0-9_-]` is never written. Where a process cannot start, the module writes
nothing and logs that once to the debug log.

### Published zone for status lines

A status line, or any other reader, can show the zone and its edges from the snapshot without
importing plugin code. Read `~/.claude/context-guard/context/<session_id>.json`, where
`<session_id>` is the `session_id` the status line's own input carries. The file holds these keys
beside `context_window`:

```json
{
  "captured_at": "2026-10-11T18:00:00Z",
  "zone": "acceptable",
  "evidence_degraded": false,
  "bands": {
    "smart_max_used_percentage": 50,
    "acceptable_max_used_percentage": 75,
    "smart_max_tokens": 100000,
    "acceptable_max_tokens": 150000
  }
}
```

- `zone` is `smart`, `acceptable`, `dumb` or `unknown`. It is computed from the bands below, and is
  `dumb` once the session was compacted.
- `bands` are the edges after `zones.json`. The token edges are for the session's window class, and
  are `null` when the token shape is not computable.
- Treat a `captured_at` older than 10 minutes as `unknown`.
- With no file, or a file without these keys (an older plugin version), use your own fallback.

These keys are part of the [reader contract](reference/reader-contract.md#snapshot-file-shape):
they change only with a major version and a changelog entry. They are written whatever
`model_notices` says.

### Where mods are off

Wherever mods are off for a session, whether the build is too old for mods or a setting, flag, policy or Claude Code itself turned them off, the
module does not run: no lines, no band, no status tool, no
module writes. The PostCompact marker, a settings hook, still runs wherever settings hooks do, and
readers fall back as the reader contract says. `/context-guard:check` and
`/context-guard:setup check` report "mods off" in that case. A hook that throws passes its event
through unchanged.

- **Pointer**: when deciding what turns mods off, and which of those also stops settings hooks,
  fetch
  [mods overview: turn mods on or off](https://code.claude.com/docs/en/plugins/mods/overview#turn-mods-on-or-off)
  and [troubleshoot: check whether mods can load](https://code.claude.com/docs/en/plugins/mods/troubleshoot#check-whether-mods-can-load)
  live.
- **As of**: 2026-10-11.
- **Recheck trigger**: either section adds or drops a way mods get turned off, or changes which
  of them stop settings hooks.

## Behavior

- **Per-session, atomic snapshots.** One file per session id (no cross-session last-writer-wins);
  readers never see torn JSON (temp file + rename, with a brief retry for the Windows
  rename-over-open-target case). Stale sibling files are pruned with a 14-day cutoff, far above the
  staleness window, so live-but-idle sessions always survive.
- **Path containment.** `session_id` becomes a filename, so the module writes only for an id of
  `[A-Za-z0-9_-]` and skips the snapshot for anything else.
- **Fail-open zone resolution.** Absent, stale, or unparsable snapshots, null or out-of-range
  `used_percentage`, null `current_usage`, a non-ISO `captured_at`, a snapshot whose embedded `session_id` differs from the
  requested one, or missing `jq` all resolve `unknown`. Consumers take their conservative path on
  data they cannot trust, never a fabricated zone. The shipped bands are declared judgment
  defaults. `zones.json` is the tuning path.
  [The reader contract](reference/reader-contract.md#zone-is-not-a-compaction-indicator) records
  how the default auto-compact thresholds relate to the bands (relayed 2026-10-11; recheck when
  that section is renamed or stops relating them). **Pointer**: when deciding what those defaults
  are, fetch
  [model config: default auto-compact thresholds](https://code.claude.com/docs/en/model-config#default-auto-compact-thresholds)
  live. **As of**: 2026-10-11. **Recheck trigger**: that table changes, or its section is renamed
  or removed. The trigger itself is
  operator-tunable, per model as well as globally; the reader contract's tunable
  table records which surfaces we rely on and where to read the rest. Bands
  belong **below** whatever it resolves to, normalized into the percentage shape, so the session
  reaches a boundary decision before the harness compacts for it. After the auto-compact window is
  lowered, we never read `used_percentage` as a forecast of when compaction will run. **Pointer**:
  when deciding what the percentage is measured against, fetch
  [environment variables: variables](https://code.claude.com/docs/en/env-vars#variables) live.
  **As of**: 2026-10-11. **Recheck trigger**: the `CLAUDE_CODE_AUTO_COMPACT_WINDOW` row changes
  what the percentage is measured against. The reader contract owns those surfaces, their
  verification dates, and the rationale.
- **Integrity boundary.** The snapshot directory is owner-only where POSIX
  modes work; on Windows ACL volumes it keeps the inherited ACLs and other local users could forge
  snapshots. Zones are routing hints. Consumers must never attach security or egress decisions
  to a zone word. See the reader contract's untrusted-data section.

### Process budget

The module's hooks run inside Claude Code and start two kinds of process. The snapshot write runs
one `node lib/write-snapshot.mjs`, at most once per changed body or per 60 seconds for an unchanged
one, which also runs the hourly prune. With `HOOK_TELEMETRY_SINK` set, each telemetry envelope
starts one sink process, not awaited: one per fire that sends lines, per operator-mode suggestion
shown. A tool call or prompt that writes nothing and sends no envelope starts
no process and writes no file; the lines start none of their own beyond that
envelope. The write is awaited inside the `tool.call`
hook, so a slow write holds that one tool result, within Claude Code's own-time limit for a hook.

- **Pointer**: [mods reference: limits](https://code.claude.com/docs/en/plugins/mods/reference#limits).
- **As of**: 2026-10-03, Claude Code 2.1.288.
- **Recheck trigger**: that section changes a hook's time limit or what happens when it is reached.

`claude plugin test plugins/context-guard` enforces it: the `budget:` case in
`hooks/context-guard.test.ts` asserts, with no telemetry sink set, no process on calls that write
nothing and one per write; the `telemetry:` cases assert one envelope per acting
fire and none on other calls; and the `floor:` case asserts the 60-second floor. The tests the module replaced, and
what holds their budget now:

| Retired test | What it held | Held now by |
|---|---|---|
| The statusline tee's suite | The snapshot body, atomic write, rename retry, prune and the processes per render | The `snapshot:` cases and the `budget:` case in `hooks/context-guard.test.ts`; the helper's own suite, [`lib/write-snapshot.test.mjs`](../../lib/write-snapshot.test.mjs), for the atomic write, rename retry, prune and temp files |
| The statusline shim's suite | The shim finding the installed tee | Nothing: no shim ships |
| The wiring compose script's suite | Composing a `statusLine` around the shim | Nothing for the shim, which no longer ships. The optional cache segment composes its own `statusLine` with `cache-line.mjs --wire`, tested in `scripts/cache-line.test.sh` |
| The crossing hook's and the PreToolUse gate's suites, process counts included | The crossing lines, the gate and the processes per fire | The line and `budget:` cases in `hooks/context-guard.test.ts`, for the lines and processes. The gate was removed, so nothing holds it |
| The hook-census ceiling on the crossing hook in `.performance/ratchets.json` | Processes per crossing-hook fire | The `budget:` case: 0 processes on a call that writes nothing |

The PostCompact marker is the one settings hook left. Per
[`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md) it fires
once per compaction. Measured on Windows 11 under Git Bash, twelve trials against an interleaved
`bash -c :` floor, old and new interleaved in one loop (2026-09-02): 9 processes to 4, 9.4
spawn-equivalents before and 5.7 after (0.7.34), with `date` replaced by printf's clock (a `date`
fallback below bash 4.2) and `mkdir` and `rm` behind existence guards. Its row keeps its
60-second timeout: an earlier measurement put a hook of this plugin at 22.0 s on Windows with
Defender real-time protection, and a timeout caps a stalled hook without speeding a normal one.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install context-guard@<marketplace>
```

Install at user scope (the default), so every session on the machine writes its snapshot. Nothing
needs wiring. `/context-guard:setup check` reports whether the mod runs and what each option is set
to; `/context-guard:setup apply` seeds `~/.claude/context-guard/zones.json` from the shipped bands
when you want a file to tune.

## Requirements

The module needs a Claude Code build at or above the terminal version mods need (older builds are
unsupported). `prerequisites.json` holds the floor as data, in `detect.version.min` of the entry
with `"id": "claude"`, which the check skill compares against (relayed 2026-10-11; recheck when
that key moves); the pointer below is where to re-derive it. Its snapshot writes and the PostCompact marker row need
[Node.js](https://nodejs.org/en/download) on `PATH`, installed on its own: we never count on Claude
Code's install to provide it. The marker and the zone resolver run on Bash (Git Bash on native Windows, so install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows)). The zone resolver,
which `/context-guard:setup check` runs, and `setup apply`'s merge into an existing `zones.json`
need [`jq`](https://jqlang.org/download/) on `PATH`; the module and the marker do not. The optional
prompt-cache status-line segment runs on Node.js too.
`/context-guard:setup check` reports these prerequisites; `/context-guard:check` reports whether
`node` and `jq` resolve. Readers own null handling for `context_window` fields.

- **Pointer**: when deciding which Claude Code version mods need, fetch
  [mods overview: turn mods on or off](https://code.claude.com/docs/en/plugins/mods/overview#turn-mods-on-or-off)
  live; when deciding whether a Claude Code install brings a Node.js the plugin could use, fetch
  [advanced setup: install with npm](https://code.claude.com/docs/en/setup#install-with-npm)
  live.
- **As of**: 2026-10-11.
- **Recheck trigger**: the terminal version that section names for mods changes, or the setup
  page says the installed binary runs on Node.js.

## Configuration

The `userConfig` options:

| Option | What it controls |
|---|---|
| `context_guard_hooks_enabled` | The module's lines and toasts, and the PostCompact marker (default `true`). Snapshot writes continue when it is off. |
| `model_notices` | The module's lines to Claude, and the operator-mode suggestions (default `false`). Off, nothing from this plugin enters Claude's context; the toast, transcript line, band row, status tool and snapshot are unchanged. |
| `zone_report_mode` | `automatic` (default) or `operator`, only with `model_notices` on; see [Operator mode](#operator-mode). |
| `zone_line_data` | What a line carries beside its zone: `percent`, `tokens`, `window` (default `zone`). |
| `context_guard_band` | The band row (default `false`); `/context-guard band on` turns it on for one session. |
| `context_guard_toast` | The toast at a zone crossing (default `true`); the transcript line stays when it is off. |

Settings outside `userConfig`:

| Setting | Where | Default | What it controls |
|---|---|---|---|
| Zone bands | `~/.claude/context-guard/zones.json` `smart_max_used_percentage`, `acceptable_max_used_percentage`, `token_bands` (see the [reader contract](reference/reader-contract.md)) | smart up to 50%, acceptable up to 75%, plus the window-class token bands | Where each zone starts. |
| `approach_margin` | `zones.json` | 5 points | How early the approach line comes; 0 turns approach lines off. |
| `actions`, `thresholds` | `zones.json` | none | An extra sentence at a zone, and extra boundaries. |
| Snapshot file a status line can read | `~/.claude/context-guard/context/<session_id>.json` | on | Written whenever the plugin is enabled; no option stops it. It carries the zone and the bands in force; see [Published zone](#published-zone-for-status-lines). |

The module reads its options when it loads. Claude Code reloads a module when its options change,
so a change takes effect from the next event, with no restart. The PostCompact marker hook reads
`context_guard_hooks_enabled` at session start.

- **Pointer**: the doc comment on `Register` in the `claude-code/index.d.ts` types Claude Code
  writes for its build (see
  [create: get the types for your build](https://code.claude.com/docs/en/plugins/mods/create#get-the-types-for-your-build)).
- **As of**: 2026-10-03, Claude Code 2.1.288.
- **Recheck trigger**: that doc comment stops saying an options change reloads the plugin.

A bad option value does not switch the module off: a `zone_line_data` item it does not know reads
as that option's default, with one transcript line naming it. An option the module does not
declare, such as a setting left from an older version, is ignored. A choice outside its list, or a
value of the wrong type, is Claude Code's to handle before the module sees it.

- **Pointer**: when deciding what Claude Code does with an option value that does not fit
  `userConfig`, fetch
  [troubleshoot: options do not fit plugin.json userConfig](https://code.claude.com/docs/en/plugins/mods/troubleshoot#options-do-not-fit-plugin-json-userconfig)
  live.
- **As of**: 2026-10-11.
- **Recheck trigger**: that section changes what Claude Code does with a refused option value.

Per-zone actions, their wording, the approach margin and extra thresholds live in
`~/.claude/context-guard/zones.json` beside the bands (shape in the
[reader contract](reference/reader-contract.md)). The snapshot path and the 10-minute staleness rule are
deliberately **not** configurable: they are contract constants that cross-plugin consumers inline
from the [reader contract](reference/reader-contract.md); a per-user override would silently split
the writer from its readers. Band numbers are the one tunable, via
`~/.claude/context-guard/zones.json` (shape in the reader contract), which any display of the
operator's own may read too, so display and consumers never drift. Disabling everything is
`enabledPlugins` / uninstall.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `context_guard_hooks_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_CONTEXT_GUARD_HOOKS_ENABLED` | Runs the module's zone lines and toasts and the PostCompact marker hook. On by default; off, none of them acts. Snapshot writes continue either way. |
| `model_notices` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_MODEL_NOTICES` | Sends Claude one line when the session enters a worse context zone, nears a boundary or passes a zones.json threshold, and restates the zone after a resume, reload or compaction (with no figures yet, says the reading is unavailable). Off by default; the rest of the plugin works either way. |
| `zone_report_mode` | string | `"automatic"` | `CLAUDE_PLUGIN_OPTION_ZONE_REPORT_MODE` | Acts only with model_notices on. automatic (default) sends the lines to Claude; operator holds them in a turn a person typed and offers the person a ready-made prompt and a notice row when the turn ends. Headless, loop and schedule turns get automatic lines either way. |
| `zone_line_data` | string | `"zone"` | `CLAUDE_PLUGIN_OPTION_ZONE_LINE_DATA` | Comma list of what a line carries beside its zone, which every line has: percent, tokens and window. Default zone. |
| `context_guard_band` | boolean | `false` | `CLAUDE_PLUGIN_OPTION_CONTEXT_GUARD_BAND` | Draws the context figure and zone in a row above the prompt. Off by default. Turn it on in /config, or for one session with /context-guard band on. |
| `context_guard_toast` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_CONTEXT_GUARD_TOAST` | Shows a short toast when the session crosses into a worse context zone, beside the transcript line that records it. On by default; off, only the transcript line remains. |

### How to set these

Three supported routes:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure context-guard@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
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

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
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
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## Consumers

The plugin's own module is the first shipped consumer, and its `mcp__context-guard__status` tool is
a zone lookup for any session that has it loaded. Next: the `plugin-quality`
audit skill (zone-informed dispatch and evidence-flush decisions, conservative on `unknown`). Any
session or tool on the machine may read the same files under the same contract.

## License

MIT (SPDX-License-Identifier: MIT).
