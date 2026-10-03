# context-guard

A Claude Code plugin that makes each session's context-window usage observable to Claude itself and
to any session or tool that needs it, so long-running workflows can route heavy work away from a
degraded context **before** quality slips, instead of guessing. Six parts:

- **The module** (`hooks/register.tsx`), a mod: a hooks module Claude Code runs in its own process.
  It tells Claude when the session crosses into a worse context zone, runs the optional blocking
  gate, draws a band row, answers the `mcp__context-guard__status` tool, and writes the snapshot
  file. It needs Claude Code 2.1.287 or later; older builds are unsupported. See
  [The module](#the-module).

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
- **PostCompact marker hook** (`hooks/post-compact-mark.sh`), a settings hook, so it runs where
  mods are off: it writes an evidence-degraded marker next to the session's snapshot, and the
  module honors it: a compacted session's effective zone is dumb regardless of its
  post-compaction numbers. Its row carries a 60-second timeout. The scripts
  `hooks/zone-crossing-inject.sh` and `hooks/zone-gate.sh` remain in the plugin but are no longer
  registered: the module is the only source of zone lines and the only gate.
- **Reader contract** (`reference/reader-contract.md`), the authoritative consumer contract: the
  snapshot path pattern, file shape, the 10-minute staleness rule, fail-open capability detection,
  the zones.json shape, session-id discovery via `${CLAUDE_SESSION_ID}`, and the
  zone-is-not-a-compaction-indicator rule. Its companion
  `reference/cloud-headless-capture.md` is the writer-side channel inventory: why the statusline is
  the only capture channel, which other channels were checked and rejected (with sources and
  dates), including the two that do carry live occupancy and still cannot supply a snapshot, and
  why `unknown` in a session that runs no statusline, a cloud or headless session by default, is
  structural rather than a defect.

## The module

The module decides from the live session's figures in interactive, `-p`, `--bg` and `/loop`
sessions alike, through a TypeScript copy of the resolver's band function over the same bands; a
shared fixture (`scripts/context-zone.fixtures.mjs`) holds the two resolvers to the same answer.
Tested with `claude plugin test` on Claude Code 2.1.288; no live run of it has been made yet.

### Lines to Claude

A line goes to Claude only at a boundary, appended to the context of a main-thread tool result or
of a prompt; a crossing seen when a turn ends reaches Claude with the next prompt. With the default
options and `zones.json`:

| When | Line |
|---|---|
| The session first reaches a worse zone this cycle | once per zone, "crossed from the <zone> into the <zone> context zone" |
| The session comes within `approach_margin` points (5) of a zone edge or a `zones.json` threshold | once per boundary, "is in the <zone> context zone, approaching ..." |
| The session passes a `zones.json` threshold | once per threshold, with the threshold's action |
| After a compaction (not the precompute kind), and after `/resume` or `/branch` | the verdict, once; after a compaction it is `dumb (evidence-degraded: this session was compacted)` |
| When the module loads into a session that already has turns (a `--resume` launch, a reload after an options change, a hooks-worker restart) | the verdict, once, only when it is past `smart` |
| After `/clear` | nothing: the new session starts in `smart` and a fresh cycle |

A dip below a boundary sends nothing and starts no new cycle; only a return to `smart` does. An
`unknown` reading sends nothing and changes nothing. Every line carries its zone word and the note
that a zone is a measurement, not an instruction, worded as facts with their source; in `dumb` it
also carries the save-state note. `zone_line_data` adds figures (percent, tokens, window); by
default a line carries none, and it never carries a session id. A configured action's sentence
(`zones.json` `actions` and `thresholds`, see the [reader contract](reference/reader-contract.md))
appears at its crossing, never before. Subagents get no line.

The operator gets the continuation menu (continue, `/compact`, `/clear`, handoff-then-`/clear`, and
the route through `/session-flow:workflow` or
[When your context fills up](https://code.claude.com/docs/en/context-window#when-your-context-fills-up))
as a transcript line Claude does not read and a band notice until the next typed prompt. The menu
never reaches Claude: an exit menu in model context manufactures the model's own initiative to stop,
summarize, or hand off, which the instruction-audit catalog flags as check I23.

### Operator mode

With `zone_report_mode` set to `operator`, a turn a person started by typing (or through the
Remote Control bridge) gets no line. When that turn ends, the line is offered as the prompt box's
suggestion (Tab takes it) and shown as a notice in the band; with text in the box, only the notice
shows, and the suggestion is offered again once the box is empty. Where nobody can take a
suggestion, the line goes to Claude as in automatic mode: `-p` and SDK turns, `/loop` and scheduled
turns, task notifications, a session with no drawing surface, and a suggestion the session reports
it cannot show. A suggestion that was shown but not taken goes to Claude as the ordinary line at
the next turn no person started (a `--bg` launch turn reads as typed, so its suggestion can go
unseen); the next typed turn instead drops it unsent. Claude Code offers no way to withdraw a
shown suggestion, so it stays in the box after that hand-off.

Upstream's render-sites table lists the band's site, `AbovePrompt`, as drawn in the terminal and
the Desktop app. No probe of this plugin ran in the Desktop app or VS Code.

- **Pointer**: [mods reference: render sites](https://code.claude.com/docs/en/plugins/mods/reference#render-sites).
- **As of**: 2026-10-03, Claude Code 2.1.288.
- **Recheck trigger**: the `AbovePrompt` row changes the apps it lists, or a Desktop run of this
  plugin is made.

### Blocking gate

With `zone_hook_mode` set to `blocking` (or a `block` action in `zones.json`), the module denies new
Write, Edit, NotebookEdit, Agent and Workflow calls in the blocked zone once the session has spent
its `zone_gate_grace_calls` budget, with a reason Claude reads. Handoff-path writes (a path that
contains "handoff"), reads, Bash and Skill calls are never gated, so a durable handoff is always
writable. Subagent calls are judged by the session's zone and count against the same budget. In a
turn a person typed the block applies; in headless, loop, schedule and notification turns only a
compacted session is blocked, unless `zone_block_unattended` is `same-as-typed`. Leaving the
blocked zone, an `unknown` reading, and a compaction each reset the budget. The gate fails open:
an `unknown` zone or a failing hook lets the call run.

### Band row and status tool

The band row above the prompt shows `[<model>] ctx <n>% (<zone>)`, the tee's standalone status line
plus the zone, and `-` before the first response. `context_guard_band` turns it off;
`/context-guard:band show`, `hide`, or no argument (toggle) changes it for the session. Claude can
call `mcp__context-guard__status` for the exact figures from the last API response, the zone,
whether a compaction degraded the evidence, the bands and the gate state. Where the session
refuses the tool's registration (an organization policy can refuse a user mod's tools), the module
logs one debug line saying so, and the lines, gate, band and writes carry on.

### Telemetry

With `HOOK_TELEMETRY_SINK` set, the module sends one envelope per
[hook-telemetry convention](../../docs/conventions/hook-telemetry/README.md) to the sink,
fire-and-forget: `zone-crossing-inject` for each tool call or prompt that sent lines (and each
operator-mode suggestion offered), and `zone-gate` with status `blocked` for each denial. A relative
sink path is joined onto the session's project root. Calls that send nothing emit nothing, so the
`path` field the shell hook reported is gone. Unset, nothing is sent.

### Snapshot writes

The module writes `~/.claude/context-guard/context/<session_id>.json` in the tee's shape through
`lib/write-snapshot.mjs`, run with `node`, which replaces it atomically, keeps the directory
owner-only on POSIX, and at most hourly prunes files older than 14 days. A changed body is written
at once; an unchanged one at most once per 60 seconds. Writes happen after every tool call, at
each measurement after a turn, from a 60-second timer that runs only while a turn runs, and at the
session's end. They follow the plugin's on/off switch only: `context_guard_hooks_enabled` and
`zone_lines_enabled` do not stop them. A session id outside `[A-Za-z0-9_-]` is never written.

Process cost: a call that writes nothing starts no process; each write starts one `node` process.
The gate and the lines start none. Mods can start host processes in the CLI only; where they
cannot, the module writes nothing and logs that once to the debug log.

### Where mods are off

Below Claude Code 2.1.287, under `disableAllHooks`, with `--bare`, when mods are switched off
remotely, or after the hooks worker crashes, the module does not run: no lines, no gate (blocking
mode does nothing), no band, no status tool, no module writes. The PostCompact marker still runs,
and readers fall back as the reader contract says. `/context-guard:check` and
`/context-guard:setup check` report "mods off" in that case. A hook that throws passes its event
through unchanged.

## Behavior

- **Transparent by contract.** No tee outcome (missing `jq`, unwritable path, or a rename blocked
  by a concurrent reader) ever changes the wrapped statusline's output or exit code. Missing `jq` is
  surfaced as a visible one-line notice, never a silent skip.
- **Per-session, atomic snapshots.** One file per session id (no cross-session last-writer-wins);
  readers never see torn JSON (temp file + rename, with a brief retry for the Windows
  rename-over-open-target case). Stale sibling files are pruned on write with a 14-day cutoff, far above the staleness window, so live-but-idle sessions always survive.
- **Cheap on every render.** A render whose context-window fields match the last write, made less
  than 60 seconds earlier (`CG_TEE_NOCHANGE_FLOOR`), writes nothing and starts no process; a render
  that writes starts one, the `mv`. The prune runs at most once an hour. A payload the built-in
  reader cannot prove byte-for-byte goes to `jq`, as before.
- **Path containment.** `session_id` becomes a filename, so the tee accepts only `[A-Za-z0-9_-]`
  and skips the snapshot for anything else, the wrapped statusline is unaffected.
- **Fail-open zone resolution.** Absent, stale, or unparsable snapshots, null or out-of-range
  `used_percentage`, null `current_usage` (early-session and post-`/compact` statusline states),
  a non-ISO `captured_at`, a snapshot whose embedded `session_id` differs from the requested one,
  or missing `jq` all resolve `unknown`. Consumers take their conservative path on data they
  cannot trust, never a fabricated zone. The shipped bands are declared judgment defaults.
  `zones.json` is the tuning path. The reader contract points at the model-config page's default
  auto-compact thresholds and records how they relate to the bands. The trigger itself is operator-tunable: `autoCompactWindow`, `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`, and
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

This section records the shell crossing hook, which is no longer registered; the module that
replaced it starts no process on a call that writes nothing (see [Snapshot writes](#snapshot-writes)).
`zone-crossing-inject.sh` ran on PostToolBatch, which fires once per tool batch, so every process
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

#### Counting invocations is not counting processes

The figures above count commands in command position, which counts `jq` and `bash` *invocations*.
That is not the number of processes the operating system creates, and the two came apart here.
Bash normally elides the extra fork inside `$(...)` and execs the command in the substitution's own
subshell, but only when that command carries no redirection of its own. A `2>/dev/null`, a `<<<`,
or a pipeline written *inside* the substitution defeats the elision, so bash forks the subshell and
then forks again to run the command. A fork that never execs never reaches a command position, so
the invocation count sees one process where the kernel made two.

Re-measured under `strace -f` (counting `clone`/`fork`/`vfork`), the steady fire that this section
reported as 3 was creating **8** processes. Each of the three call sites carried its redirection
inside the substitution and so cost double, and the payload pass cost triple because it was fed by
a `printf | jq` pipeline. Moving every redirection onto an enclosing `{ ...; }` group, and reading
the payload into a variable in-process rather than through a command substitution, brings the real
count to 3, the figure this section always claimed:

| Steady PostToolBatch fire | Process creations | Program launches (`execve`) |
|---|---|---|
| Before ([#3520](https://github.com/melodic-software/claude-code-plugins/issues/3520)) | 8 | 4 |
| After | 3 | 4 |

The program launches are unchanged, which is the point: the same `jq`, `bash` and `jq` still run
over the same inputs, and only the fork overhead around them is gone. On the hosts in
[#3508](https://github.com/melodic-software/claude-code-plugins/issues/3508) a process creation
costs 180 to 2,841 ms (median 1,108 ms at 501 concurrent processes) against about 1% user CPU, so
removing five of eight is the whole of the available saving on that class of host. This hook draws
on the per-turn ceiling as well as the per-tool-call one, because it fires on `UserPromptSubmit`
too.

Which hooks this reaches: the zone-crossing hook on both of its routes (`PostToolBatch` and
`UserPromptSubmit`), and the `PreToolUse` zone gate, which calls the same resolver and so inherits
its share. Not the `PostCompact` marker: `post-compact-mark.sh` never calls the resolver and still
captures its payload through a command substitution, so its count is untouched by this pass.

The contract test asserts the process-creation count under `strace` as an exact figure, alongside
the older command-position budget, so a redirection moved back inside a substitution fails a test
rather than quietly doubling a call site. Where `strace` is unavailable that assertion skips and
the command-position budget still runs.

#### Skipping the resolve when nothing moved

Three files outside the hook decide everything it does: the per-session snapshot, the optional
`zones.json`, and the compaction marker. When none is newer than the `.seen` mark the last
completed resolve left, and the two optional ones still exist or are still absent exactly as that
mark's own line records them, the fire cannot reach a different answer, and the hook exits through
builtins alone. The existence line is what an mtime comparison cannot supply: a removed file is
never newer than anything, so without it, deleting `zones.json` or the compaction marker read as
nothing having moved. A mark carrying no readable line never takes the skip. The envelope parse had
to become free for any of this to mean anything, so a payload
within `hook::jq_fields`' proof ceiling is parsed by the library's builtin JSON parser, and one
above it keeps the single here-string `jq` described below.

Measured as process creations under a Windows job object, which counts every descendant; 5 reps per
cell, identical across reps. The subject is the hooks.json row run through `usr/bin/bash.exe -c`,
whose own floor is 3: the `-c` shell, `env`, and the shell the script's shebang starts.

| Fire | Payload | Creations before | After |
|---|---|---|---|
| First, resolves | small envelope | 11 | 9 |
| Repeat, nothing moved | small envelope | 9 | **3** |
| Snapshot rewritten | small envelope | 9 | 7 |
| First, resolves | 150 KB batch | 11 | 11 |
| Repeat, nothing moved | 150 KB batch | 9 | **5** |
| Snapshot rewritten | 150 KB batch | 9 | 9 |

No cell is worse than before, which is what the size test on the envelope parse buys: the helper's
fallback reads through a process substitution and costs four creations on an oversize payload
against two for the here-string `jq`, so only the small arm goes through the helper. Wall clock on
this host is bimodal and is reported only for the row it dominates: the small repeat fire's median
fell from 1,448 ms to 237 ms.

The one failure mode is a snapshot written DURING a resolve. The mark is stamped after the resolve
completes, so that write counts as seen and its crossing waits for the next statusline render; the
window is the resolve, not an mtime tick. A missed crossing is therefore late, never lost, and the
converse cannot happen: skipping only ever chooses silence, so no arrangement of timestamps can
manufacture an injection the full path would not have made.

#### Oversize envelope, unchanged inputs

The 150 KB repeat row above paid a here-string `jq` before the unchanged-input skip could run, because the skip needs `session_id`. On a `PostToolBatch` envelope those ids are top-level strings and `tool_calls` is the nested value that makes the payload large (hooks reference: common fields include `session_id` and `hook_event_name`; `PostToolBatch` adds `tool_calls`). The hook now closes a leading scalar object at the comma before that first nested value and parses the two ids with the builtin parser. The skip then exits with no external command, the same budget as a small envelope. Ids that follow the nested value, or a header the scan cannot prove, still use the here-string `jq`. A rewrite whose zone inputs changed still resolves, so a crossing is not dropped. A rewrite that only refreshes `captured_at`, or that keeps `used_percentage` inside the same shipped band with every other field unchanged and no `zones.json`, reuses the last zone and starts no resolver. `zone-crossing-inject.test.sh` pins both arms by xtrace.

#### The cost this pass added: a temp file on payloads over 64KiB

The saving is not free, and the charge is disk rather than CPU. Two of the five removed process
creations come from replacing `printf '%s' "$INPUT" | jq` with `jq` fed by `<<<"$INPUT"`, and a
here-string is not a pipe. Bash 5.1+ delivers one through the pipe buffer only while it fits; at or
above 64KiB it writes the string to a temp file (`/tmp/sh-thd.*`) and hands `jq` that descriptor.
Measured on bash 5.2.21: a 60,000-byte here-string opens no file, a 65,536-byte one opens
`/tmp/sh-thd.*` twice (create, then read). The pipeline this replaced never touched disk at any
size.

The extracted fields are byte-identical either way, so this changes no output. But a
`PostToolBatch` payload carries every serialized tool result and routinely clears 64KiB, so a large
fire now performs a temp-file write and read it did not perform before. That lands on the platform
this work is for: the #3508 hosts run Defender real-time protection, which scans temp-file writes,
and the 0.4.8 measurement below already attributes 22.0 s on that platform to it. The trade taken
is one process creation saved on **every** fire against disk I/O on the fires that exceed the
buffer, on hosts where a process creation costs 180 to 2,841 ms. Handing the hook's stdin straight
to `jq` would avoid both, and is declined for a separate reason: it would give up `payload.sh`'s
bounded `read -t 5` drain loop, which caps a stalled pipe at five seconds instead of letting it
block to the harness timeout. That loop is builtins only and costs no process, so keeping it is not
what the here-string pays for.

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

The module needs Claude Code 2.1.287 or later (older builds are unsupported) and Node.js on `PATH`
for its snapshot writes. The scripts run on Bash (Git Bash on native Windows, so install
[Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows); the statusline wiring
invokes `bash` explicitly) and need [`jq`](https://jqlang.org/download/) on `PATH` for the tee, the
zone resolver, and the standalone statusline. Every hook row runs through `node hooks/exec-bash.mjs`,
so the hooks need [Node.js](https://nodejs.org/en/download) on `PATH`: Claude Code's native binary
neither ships nor uses Node ([setup](https://code.claude.com/docs/en/setup)), and without it the
hooks do not launch and are not enforced. The statusline tee does not use Node.
`/context-guard:setup check` reports both prerequisites; `/context-guard:check` reports whether `node` and `jq` resolve. The snapshot updates only while an interactive
session refreshes the statusline; `context_window` fields can be `null` early in a session and
right after `/compact`, per the
[statusline reference](https://code.claude.com/docs/en/statusline). Readers own null handling.

Cost: the tee adds roughly 0.6–0.9 s per statusline refresh on Windows under Git Bash, where the
cost is process-spawn bound on `jq` and `date`, and correspondingly less on native POSIX shells. The statusline is not on
the input path, so this is display latency, not typing latency; `refreshInterval` in your settings
governs how often it runs.

### Hook budget accounting

Per [`docs/conventions/hook-budget/README.md`](../../docs/conventions/hook-budget/README.md),
the PostToolBatch and UserPromptSubmit rows were per-turn hooks and the PreToolUse row
per-tool-call, all always-on; those three rows now live in the module, whose `tool.call` and
`prompt.submit` hooks are always-on in process and start a process only to write a snapshot (one
`node`, at most once per changed body or 60 seconds). The PostCompact row is the one settings hook
left. The table records the shell rows as measured. Measured on Windows 11 under Git Bash, twelve trials against an
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

The spawn-equivalents above are command-position counts. Re-measured as process creations under
`strace -f` (0.7.49), the steady PostToolBatch and UserPromptSubmit fire was creating 8 processes
where those rows report 3; moving every redirection off the inside of a command substitution
brings it to 3 with the program launches unchanged. See "Counting invocations is not counting
processes" above for why the two counts differ and what it costs on a slow-spawn host.

The two advisory rows keep their 60-second timeout: the 0.4.8 measurement put this script at
22.0 s on Windows with Defender real-time protection, and a timeout caps a stalled hook without
speeding a normal one.

## Configuration

The `userConfig` options:

| Option | What it controls |
|---|---|
| `context_guard_hooks_enabled` | The module's lines and gate, and the PostCompact marker (default `true`). Snapshot writes continue when it is off. |
| `zone_lines_enabled` | The module's lines to Claude, and the operator-mode suggestions (default `true`). |
| `zone_report_mode` | `automatic` (default) or `operator`; see [Operator mode](#operator-mode). |
| `zone_line_data` | What a line carries beside its zone: `percent`, `tokens`, `window` (default `zone`). |
| `zone_hook_mode` | `advisory` (default) or `blocking`; see [Blocking gate](#blocking-gate). |
| `zone_gate_grace_calls` | Blocking's grace budget (default 20). |
| `zone_block_unattended` | `post-compaction` (default) or `same-as-typed`: what unattended turns get in blocking. |
| `context_guard_band` | The band row (default `true`). |

The module reads its options when it loads. Claude Code reloads a module when its options change,
so a change takes effect from the next event, with no restart. The PostCompact marker hook reads
`context_guard_hooks_enabled` at session start, as before.

A bad option value does not switch the module off: a `zone_gate_grace_calls` that is not a whole
number from 0 to 999999999, or a `zone_line_data` item it does not know, reads as that option's
default, with one transcript line per option naming it, and a choice outside its list reads as its
default with Claude Code's own line. A value of the wrong type (text in a number or on/off option)
is still refused by Claude Code, which then loads none of the module.

- **Pointer**: the doc comment on `Register` in the `claude-code/index.d.ts` types Claude Code
  writes for its build (see
  [create: get the types for your build](https://code.claude.com/docs/en/plugins/mods/create#get-the-types-for-your-build)).
- **As of**: 2026-10-03, Claude Code 2.1.288.
- **Recheck trigger**: that doc comment stops saying an options change reloads the plugin.

Per-zone actions, their wording, the approach margin and extra thresholds live in
`~/.claude/context-guard/zones.json` beside the bands (shape in the
[reader contract](reference/reader-contract.md)). The snapshot path and the 10-minute staleness rule are
deliberately **not** configurable: they are contract constants that cross-plugin consumers inline
from the [reader contract](reference/reader-contract.md); a per-user override would silently split
the writer from its readers. Band numbers are the one tunable, via
`~/.claude/context-guard/zones.json` (shape in the reader contract), which the operator's own
statusline display may read too, so display and consumers never drift. Disabling the tee is the
operator's edit (remove or unwrap the statusline command); disabling everything is
`enabledPlugins` / uninstall.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `context_guard_hooks_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_CONTEXT_GUARD_HOOKS_ENABLED` | Runs the module's zone lines and blocking gate and the PostCompact marker hook. On by default; off, none of them acts. Snapshot writes continue either way. |
| `zone_lines_enabled` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_ZONE_LINES_ENABLED` | Sends Claude one line when the session crosses into a worse context zone, approaches a boundary, or passes a zones.json threshold, and restates the zone after a compaction, a resume or a reload. On by default. |
| `zone_report_mode` | string | `"automatic"` | `CLAUDE_PLUGIN_OPTION_ZONE_REPORT_MODE` | automatic (default) sends the lines to Claude; operator holds them in a turn a person typed and offers the person a ready-made prompt and a band notice when the turn ends. Headless, loop and schedule turns get automatic lines either way. |
| `zone_line_data` | string | `"zone"` | `CLAUDE_PLUGIN_OPTION_ZONE_LINE_DATA` | Comma list of what a line carries beside its zone, which every line has: percent, tokens and window. Default zone. |
| `zone_hook_mode` | string | `"advisory"` | `CLAUDE_PLUGIN_OPTION_ZONE_HOOK_MODE` | advisory (default) sends lines only; blocking also denies new Write, Edit, NotebookEdit, Agent and Workflow calls in the dumb zone past the grace budget, unless zones.json sets an action for the dumb zone. Handoff-path writes, reads, Bash and Skill stay allowed, and an unknown zone fails open. |
| `zone_gate_grace_calls` | number | `20` | `CLAUDE_PLUGIN_OPTION_ZONE_GATE_GRACE_CALLS` | Blocking only: matched tool calls allowed after the session first reaches a blocked zone, before the gate denies. Default 20; 0 denies the first matched call; a value that is not a whole number from 0 to 999999999 reads as 20. |
| `zone_block_unattended` | string | `"post-compaction"` | `CLAUDE_PLUGIN_OPTION_ZONE_BLOCK_UNATTENDED` | post-compaction (default): in turns no person typed (headless, loop, schedule and notification turns) only a compacted session is blocked; same-as-typed blocks them as typed turns are. |
| `context_guard_band` | boolean | `true` | `CLAUDE_PLUGIN_OPTION_CONTEXT_GUARD_BAND` | Draws the context figure and zone in a row above the prompt. On by default; /context-guard:band shows or hides it for the session. |

### How to set these

Three supported routes, in the order most people want them:

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

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## Consumers

The plugin's own module is the first shipped consumer, and its `mcp__context-guard__status` tool is
a zone lookup for any session that has it loaded. Next: the `plugin-quality`
audit skill (zone-informed dispatch and evidence-flush decisions, conservative on `unknown`). Any
session or tool on the machine may read the same files under the same contract.

## License

MIT (SPDX-License-Identifier: MIT).
