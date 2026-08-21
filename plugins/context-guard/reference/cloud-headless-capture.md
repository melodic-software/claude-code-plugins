# Context guard — capture channels in cloud and headless sessions

Why the statusline tee is this plugin's only capture source, which other channels were checked and
rejected, and how a consumer tells a *structurally absent* instrument from a *broken* one.

`reference/reader-contract.md` remains the authoritative reader-side contract: snapshot path
pattern, staleness rule, zone bands, combination rule. This file is the **writer-side channel
inventory** — where a snapshot can come from, and what to expect where none can.

## Verdict

**As of 2026-08-21, no documented Claude Code channel other than the status line delivers
per-session context-window occupancy to a local writer.** Two other channels do carry real
occupancy numbers for the running session, and neither can be turned into a snapshot: the
OpenTelemetry `claude_code.api_request` log event carries live per-session token counts but no
window size and reaches only an out-of-process receiver, and the session transcript carries the
same numbers behind an explicitly unsupported entry format. Both are recorded in full below rather
than waved off.

Hook stdin — the named candidate — carries no context, token, usage, or window field on any event,
**except `PostToolUse` on the `Agent` tool, whose `tool_response` carries `totalTokens` and a
`usage` breakdown for the *subagent's* final API request — nothing about the main session's
window.**

In a session where no `statusLine` is configured, or where one is configured and the environment
never runs it, no snapshot is written, so `context-zone.sh` answers `unknown` and every zone
consumer takes its conservative path. **That `unknown` is structural, not a defect and not a broken
install.**

The evidence for each channel is below, with the live URL and the date it was read.

## Current-state facts (measured, not inferred)

Measured **2026-08-21** inside a live Claude Code on the web container
(`CLAUDE_CODE_ENTRYPOINT=remote`, `CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE=cloud_default`,
`claude --version` reporting `2.1.235 (Claude Code)`).

| Observation | Command | Result |
|-------------|---------|--------|
| Is a status line configured? | `grep -rn statusLine ~/.claude/settings.json ~/.claude/launcher-settings.json ~/.claude/remote-settings.json ~/.claude/policy-limits.json .claude/settings.json .claude/settings.local.json /etc/claude-code/managed-settings.json` | no match in any scope that exists; the local and managed files do not exist in this container |
| Does the contract directory exist? | `ls -la ~/.claude/context-guard/` | exists, containing only `context/` |
| Does a snapshot exist? | `ls -la ~/.claude/context-guard/context/` | only `<session_id>.compacted` (the `PostCompact` marker); **no `<session_id>.json`** |
| What does the resolver return? | `bash scripts/context-zone.sh <session_id>` | `unknown` |
| Does a **configured** `statusLine` run in a cloud session? | wrote a `statusLine` into the live session's `~/.claude/settings.json` with `refreshInterval: 2`, pointing at a probe that appends its stdin to a log *before* handing it to the tee, then exercised the session for ~7 minutes and restored the file | **the probe was never invoked once** — no log entry, no `<session_id>.json`. The probe itself was verified working by feeding it a payload by hand (it logged, teed a snapshot, and printed a statusline row) |
| Does a **configured** `statusLine` run in a headless session? | the identical `statusLine` in a scratch `HOME`, exercised with `claude -p '…' --output-format json` | **same** — the probe was never invoked, and `~/.claude/context-guard/` was never created under that `HOME` |
| Does the resolver accept an occupancy-only snapshot with no window size? | synthetic snapshots under a scratch `HOME` | **no.** With `cli_version`, `current_usage` and both token totals present but `context_window_size` absent and `used_percentage` null → `unknown`; adding a `context_window_size` to the otherwise identical file → `acceptable`. A snapshot with no `current_usage` is rejected by the trust gate outright, whatever else it carries |

The central claim is **confirmed with one correction**: `~/.claude/context-guard/` *does* exist in
a cloud container, but only because a hook created it. The **snapshot** the reader needs is absent,
and the resolver prints `unknown`.

**The reader side is healthy; only the writer channel is missing.** In the same container, feeding
the resolver one synthetic statusline payload under a scratch `HOME` — 120000 input + 3000 output
tokens in a 200000 window, `used_percentage` 60 — produced a snapshot and resolved `acceptable`,
while the real session id resolved `unknown` moments earlier. Nothing about `context-zone.sh`,
`statusline-tee.sh`, `jq`, or the contract path is broken here. There is simply nothing calling the
tee, because nothing calls a statusline.

**The cloud row is a measurement, not an inference.** The earlier version of this file established
only that no `statusLine` *is* configured in cloud and inferred the rest. The row above closes that
gap from the other side: one *was* configured, in the user scope of a live cloud session, and it
never ran. The write was live rather than pending a restart — Claude Code "watches your settings
files and reloads them when they change", the reload "covers user, project, local, and managed
settings", and `statusLine` is not among the few keys documented as read once at session start
(<https://code.claude.com/docs/en/settings>, read 2026-08-21). The headless half was measured the
same day by the same method: the identical `statusLine` written into a scratch `HOME`, exercised
with `claude -p '…' --output-format json`, again never invoked the probe and never created
`~/.claude/context-guard/` at all.

The correction matters. The `.compacted` marker in that directory was written by
`hooks/post-compact-mark.sh` during an auto-compaction of that session, which proves **plugin hooks
do run in this environment**. The status line is the only context-guard writer that is silent in
cloud — the hook layer is alive. That is why hook stdin was the first channel checked, and why its
field set is the decisive negative result rather than an assumption.

## Channels checked

Every row was read from the live page on **2026-08-21**. Claims below are quoted or paraphrased
from those pages, not recalled.

| Channel | Source read | Carries | Does **not** carry |
|---|---|---|---|
| Hook stdin (all events) | <https://code.claude.com/docs/en/hooks> | Common input fields: `session_id`, `prompt_id`, `transcript_path`, `cwd`, `permission_mode`, `effort`, `hook_event_name`, plus `agent_id` / `agent_type` under an agent. Event-specific fields such as `tool_name`, `tool_input`, `tool_use_id`. **One event carries token figures:** `PostToolUse` on the `Agent` tool receives `totalTokens` ("Token count from the subagent's final API request: input, output, and cache tokens combined. This isn't a total across the whole run") and a `usage` object (`input_tokens`, `output_tokens`, `cache_creation_input_tokens`, `cache_read_input_tokens`) in `tool_response` | Any context-window, token-count, usage, or percentage-of-window field for the **main session**, on any event. The `Agent` exception is subagent-scoped and single-request-scoped — the page says outright it "isn't a total across the whole run" — and it is absent entirely for background subagents. `effort` is a reasoning-effort level, not consumption |
| Status line stdin | <https://code.claude.com/docs/en/statusline> | The whole `context_window` object — `total_input_tokens`, `total_output_tokens`, `context_window_size`, `used_percentage`, `remaining_percentage`, `current_usage` — plus top-level `version` | Nothing this plugin needs. This is the one sufficient channel, and it exists only where a `statusLine` is configured *and* the environment runs it |
| `subagentStatusLine` stdin | <https://code.claude.com/docs/en/statusline> | A `tasks` array whose entries carry `tokenCount` and `contextWindowSize` per subagent row | Any figure for the **main session**. It describes subagent rows in the agent panel, and it is a status-line-family surface, so it is absent wherever the status line is |
| Non-interactive / Agent SDK output | <https://code.claude.com/docs/en/headless> | `--output-format json` returns result, session ID, usage and `total_cost_usd` for **that invocation**; `stream-json` emits per-event metadata | Live occupancy of an already-running interactive session. It reports on a run the caller starts, after the fact — it cannot answer "how full is this session's window right now" |
| OpenTelemetry **metrics** | <https://code.claude.com/docs/en/monitoring-usage> | `claude_code.token.usage`, a **counter** with `type` attributes `input` / `output` / `cacheRead` / `cacheCreation` | Any gauge of current occupancy or percentage of window. Every documented metric is a counter of cumulative activity, and a cumulative total is not observable as current occupancy |
| OpenTelemetry **events** (`claude_code.api_request`) | <https://code.claude.com/docs/en/monitoring-usage> | **Real live occupancy, per session.** The event carries `input_tokens`, `output_tokens`, `cache_read_tokens` and `cache_creation_tokens` for each request, `query_source` naming the subsystem that issued it (`"repl_main_thread"`, `"compact"`, or a subagent name), `event.sequence` for ordering within a session, and `session.id` as a standard attribute (`OTEL_METRICS_INCLUDE_SESSION_ID`, default **true**). The three input addends on the latest `repl_main_thread` event are the same sum the statusline page gives for `used_percentage` | `context_window_size`, or any percentage — see below. And any local delivery: events go only to an OTLP receiver or the `console` exporter (`prometheus` accepts metrics only, and `console` writes to Claude Code's own stdout), and Claude Code "doesn't pass `OTEL_*` environment variables to the subprocesses it spawns, including the Bash tool, hooks, MCP servers, and language servers" |
| Session transcript file | <https://code.claude.com/docs/en/sessions> | The JSONL at `~/.claude/projects/<project>/<session-id>.jsonl`, reachable from every hook through the documented `transcript_path` field | A **supported** shape to parse. See below — this is the second near-miss and it is disqualified deliberately |
| Cloud session environment | <https://code.claude.com/docs/en/claude-code-on-the-web> | Confirmation that cloud sessions run hooks and read committed settings files, and that `/context` and `/compact` work there | Any statement that a status line runs in a cloud session, and any cloud-specific telemetry surface. The page's context-management section lists `/compact`, `/context`, `/clear` and never mentions `statusLine` |

## The OTel `api_request` event carries occupancy, and still cannot be a capture path

This is the channel that most nearly falsifies the verdict, so its rejection is recorded in full
rather than folded into a table cell. It is **not** rejected on the grounds that OpenTelemetry only
exposes cumulative counters — that is true of the *metrics* and false of the *events*.

`claude_code.api_request` is a documented log event
(<https://code.claude.com/docs/en/monitoring-usage>, read 2026-08-21) carrying `input_tokens`,
`output_tokens`, `cache_read_tokens` and `cache_creation_tokens` per request, plus `query_source`
identifying the issuing subsystem and `event.sequence` for ordering. `session.id` is a standard
attribute on every event and is on by default. Filtering to the newest `repl_main_thread` event for
a session therefore yields the current main-thread occupancy — the same three input addends the
statusline page names as the `used_percentage` formula
(<https://code.claude.com/docs/en/statusline>, read 2026-08-21): "`input_tokens +
cache_creation_input_tokens + cache_read_input_tokens`". This channel really does supply live,
per-session occupancy for a running interactive session.

Two disqualifiers hold anyway, and both were measured rather than assumed.

**It carries no denominator.** The event has no `context_window_size` and no percentage. The
resolver needs one or the other: the percentage shape reads `used_percentage`, and the token shape
selects a band row by window class from `context_window_size`. Measured under a scratch `HOME`: a
snapshot carrying `cli_version`, a mapped `current_usage`, both token totals, a null
`used_percentage` and **no** `context_window_size` resolves `unknown`; adding a
`context_window_size` to the otherwise identical file resolves `acceptable`. A writer built on this
event would have to invent that number from a hard-coded per-model window map, which is exactly the
fabricated denominator this contract forbids — and it would go wrong silently the first time a
model shipped with a different window.

**It has no local delivery.** Events reach an OTLP receiver or the `console` exporter; `prometheus`
is listed for metrics only, and `console` writes to Claude Code's own stdout rather than to a file
a hook could read. There is no in-process or on-disk sink. Worse for a hook-local writer, the same
page states that Claude Code "doesn't pass `OTEL_*` environment variables to the subprocesses it
spawns, including the Bash tool, hooks, MCP servers, and language servers", so a hook cannot even
discover where the telemetry is going. Making this a capture path means standing up and operating
an out-of-process collector, and a plugin that ships a zone instrument only for operators who run
an OTLP pipeline has not solved the problem this file exists for.

The plugin therefore does **not** ship an OTel-derived capture path. The channel is recorded here
because it is genuinely the closest documented substitute, and a future reader deserves the real
reason rather than a claim about counters that its own citation disproves.

## The transcript is reachable, and still not a viable source

The second near-miss, and the rejection is likewise recorded in full.

Every hook receives `transcript_path`, and the sessions page explicitly lists reading it as one of
the supported ways to "React to session events". The file is live: in the measured container it was
being appended to continuously, and each assistant entry carries a `usage` object whose
`input_tokens`, `cache_creation_input_tokens` and `cache_read_input_tokens` are exactly the three
addends the status line page says `used_percentage` is computed from. A hook could read the last
such entry and write a snapshot with no status line involved.

The sessions page disqualifies the parse (<https://code.claude.com/docs/en/sessions>, read
2026-08-21):

> Each line is a JSON object for a message, tool use, or metadata entry. The entry format is
> internal to Claude Code and changes between versions, so scripts that parse these files directly
> can break on any release.

**That warning alone is not sufficient grounds, and this file will not pretend it is.** A reader
that validates shape before emitting — all three keys present, integral, non-negative, their sum
inside a known window, the entry's timestamp recent, and nothing emitted on any assertion failure —
degrades on a breaking format change to writing *no snapshot*, which resolves to `unknown`. That is
the same fail-open posture this contract mandates everywhere else, and this file already calls
`unknown` an acceptable outcome. "It would produce a confident wrong zone" is not what a
shape-validating reader does.

The decision stands on the failure a shape check cannot catch: **silent semantic drift.** The
disclaimer covers meaning as well as structure. `input_tokens` can keep its name, its type and its
plausible magnitude while ceasing to denote full-context occupancy — a per-turn delta after a
restructuring, a post-summarization figure, a count excluding some newly separate block. Every
shape assertion still passes, the reader still emits, and the zone is wrong with no signal
anywhere. Against a format whose maintainers have explicitly declined to promise stability, the
only defense is re-verifying the *semantics* of three fields against a live session on every Claude
Code release — an unbounded maintenance obligation this plugin would be taking on unilaterally, for
a channel whose owners have told it not to.

The plugin therefore does **not** ship a transcript-derived capture path.

## What this means for consumers

- **`unknown` in a session with no configured `statusLine` is the expected steady state.** Report
  it as "no instrument in this environment", never as a broken install, a missing dependency, or a
  reason to ask the operator to fix something.
- **The conservative path is still correct.** Nothing here changes the fail-open rule: `unknown`
  means take the conservative route.
- **Do not synthesize a zone from any other source.** The three reachable near-substitutes — the
  cumulative OTel counter, the OTel `api_request` event with no window size, and the transcript's
  internal entry format — each require inventing or trusting something the channel does not supply.
- **Cost of the gap.** The instrument is absent exactly where sessions are most disposable, so an
  instrument-driven handoff or fork trigger cannot fire there. A consumer that wants a handoff
  trigger in a cloud or headless session must drive it from something other than a zone reading —
  an explicit operator request, or an observation the consumer makes itself. It must not treat
  `unknown` as evidence of a full window; `unknown` carries no direction.

## Distinguishing structural absence from breakage

Both states print `unknown`, so the discriminator is the writer side, and it is doc-backed:
the status line runs only where a `statusLine` command is configured and the environment is one
that runs it (<https://code.claude.com/docs/en/statusline>,
<https://code.claude.com/docs/en/settings>, both read 2026-08-21).

1. Read `statusLine` from every settings scope that can carry it — user `~/.claude/settings.json`,
   project `.claude/settings.json`, local `.claude/settings.local.json`, and managed settings
   (`/etc/claude-code/managed-settings.json` and the platform equivalents, where `statusLine` is
   also a valid key).
2. **No `statusLine` in any scope** → structural. No snapshot can be written for this session by
   any mechanism this plugin ships. `unknown` is correct and final until a status line is
   configured *and* the environment runs one.
3. **A `statusLine` is configured but the status line is disabled** → also structural, and the
   remediation is policy or trust rather than wiring. Claude Code turns the feature off entirely
   when managed settings set `disableAllHooks`, or when the folder is not trusted under the same
   workspace-trust rule that gates hooks in settings files; and it narrows the source to managed
   settings when `allowManagedHooksOnly` is set. Under narrowing, "Claude Code runs a managed value
   if one is deployed; otherwise it skips your value without warning, the status line is disabled".
   A configured `statusLine` that never runs looks exactly like a broken install unless this branch
   is checked first.
4. **A `statusLine` is configured, the status line is not disabled, and no fresh snapshot exists**
   → a real defect: wiring, the installed shim, or `jq`. Invoke `/context-guard:setup` via the
   Skill tool with `check` for the full diagnosis.

A cloud or headless session lands on branch 2 by default: no `statusLine` is configured. It also
lands on the structural side when one *is* configured — measured above, a `statusLine` written into
a live cloud session's user settings was never invoked. The status line is a terminal-interface
surface: the page describes it rendering above the footer badges and reading `COLUMNS` / `LINES`
for terminal dimensions. Configuring one there is not a remediation to offer.

## What would have to change upstream

Any **one** of these would make a cloud- and headless-compatible capture path possible, and each is
a change to Claude Code, not to this plugin:

- **A context field on hook stdin.** The smallest sufficient change: add the `context_window`
  object (or its `used_percentage` alone) to the documented common input fields. Every hook already
  receives `session_id`, so a `PostToolBatch` or `UserPromptSubmit` hook could write the existing
  snapshot shape with no new contract on the reader side.
- **A documented, stable transcript entry schema** — at minimum a versioned, supported shape for
  the per-message `usage` object, with its *semantics* pinned and not only its field names — which
  would convert that near-miss into a real channel.
- **A documented status-line equivalent that runs without a terminal**, or a statement that cloud
  sessions run a configured `statusLine`. The statusline page documents neither: it describes the
  status line as "a customizable bar at the bottom of Claude Code" rendering "in its own row above
  the built-in footer badges", sized from the `COLUMNS` and `LINES` terminal dimensions, and names
  no non-terminal equivalent and no cloud behavior (<https://code.claude.com/docs/en/statusline>,
  read 2026-08-21).
- **A `context_window_size` attribute on the `claude_code.api_request` event, plus a local sink.**
  The event already carries the occupancy numerator; a denominator and a file- or stdio-based
  delivery a hook could read would make it sufficient. Either half alone is not enough.

Re-check this file against the pages above when Claude Code's hooks, status line, settings or
telemetry reference changes. The finding is dated, not permanent.
