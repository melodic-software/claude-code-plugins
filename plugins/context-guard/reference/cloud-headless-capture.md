# Context guard — capture channels in cloud and headless sessions

Why the statusline tee is this plugin's only capture source, which other channels were checked and
rejected, and how a consumer tells a *structurally absent* instrument from a *broken* one.

`reference/reader-contract.md` remains the authoritative reader-side contract: snapshot path
pattern, staleness rule, zone bands, combination rule. This file is the **writer-side channel
inventory** — where a snapshot can come from, and what to expect where none can.

## Verdict

**As of 2026-08-21, no documented Claude Code channel other than the status line carries
per-session context-window telemetry.** Hook stdin — the named candidate — carries no context,
token, usage, or window field on any event. In a session where no `statusLine` is configured, no
snapshot can be written, so `context-zone.sh` answers `unknown` and every zone consumer takes its
conservative path. **That `unknown` is structural, not a defect and not a broken install.**

The evidence for each channel is below, with the live URL and the date it was read.

## Current-state facts (measured, not inferred)

Measured **2026-08-21** inside a live Claude Code on the web container
(`CLAUDE_CODE_ENTRYPOINT=remote`, `CLAUDE_CODE_REMOTE_ENVIRONMENT_TYPE=cloud_default`,
`claude --version` reporting `2.1.235 (Claude Code)`).

| Observation | Command | Result |
|-------------|---------|--------|
| Is a status line configured? | `grep -rn statusLine ~/.claude/settings.json ~/.claude/launcher-settings.json ~/.claude/remote-settings.json ~/.claude/policy-limits.json` | no match in any scope; `/etc/claude-code/managed-settings.json` does not exist |
| Does the contract directory exist? | `ls -la ~/.claude/context-guard/` | exists, containing only `context/` |
| Does a snapshot exist? | `ls -la ~/.claude/context-guard/context/` | only `<session_id>.compacted` (the `PostCompact` marker); **no `<session_id>.json`** |
| What does the resolver return? | `bash scripts/context-zone.sh <session_id>` | `unknown` |

The central claim is **confirmed with one correction**: `~/.claude/context-guard/` *does* exist in
a cloud container, but only because a hook created it. The **snapshot** the reader needs is absent,
and the resolver prints `unknown`.

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
| Hook stdin (all events) | <https://code.claude.com/docs/en/hooks> | Common input fields: `session_id`, `prompt_id`, `transcript_path`, `cwd`, `permission_mode`, `effort`, `hook_event_name`, plus `agent_id` / `agent_type` under an agent. Event-specific fields such as `tool_name`, `tool_input`, `tool_use_id` | **Any context-window, token-count, usage, or percentage-of-window field, on any event.** `effort` is a reasoning-effort level, not consumption |
| Status line stdin | <https://code.claude.com/docs/en/statusline> | The whole `context_window` object — `total_input_tokens`, `total_output_tokens`, `context_window_size`, `used_percentage`, `remaining_percentage`, `current_usage` — plus top-level `version` | Nothing this plugin needs. This is the one sufficient channel, and it exists only where a `statusLine` is configured and refreshing |
| `subagentStatusLine` stdin | <https://code.claude.com/docs/en/statusline> | A `tasks` array whose entries carry `tokenCount` and `contextWindowSize` per subagent row | Any figure for the **main session**. It describes subagent rows in the agent panel, and it is a status-line-family surface, so it is absent wherever the status line is |
| Non-interactive / Agent SDK output | <https://code.claude.com/docs/en/headless> | `--output-format json` returns result, session ID, usage and `total_cost_usd` for **that invocation**; `stream-json` emits per-event metadata | Live occupancy of an already-running interactive session. It reports on a run the caller starts, after the fact — it cannot answer "how full is this session's window right now" |
| OpenTelemetry metrics and events | <https://code.claude.com/docs/en/monitoring-usage> | `claude_code.token.usage`, a **counter** with `type` attributes `input` / `output` / `cacheRead` / `cacheCreation` | Any gauge of current occupancy or percentage of window. Every documented metric is a counter of cumulative activity; a cumulative total is not observable as current occupancy — precisely the failure the resolver's token-shape version gate exists to prevent |
| Session transcript file | <https://code.claude.com/docs/en/sessions> | The JSONL at `~/.claude/projects/<project>/<session-id>.jsonl`, reachable from every hook through the documented `transcript_path` field | A **supported** shape to parse. See below — this is the near-miss and it is disqualified deliberately |
| Cloud session environment | <https://code.claude.com/docs/en/claude-code-on-the-web> | Confirmation that cloud sessions run hooks and read committed settings files, and that `/context` and `/compact` work there | Any statement that a status line runs in a cloud session, and any cloud-specific telemetry surface. The page's context-management section lists `/compact`, `/context`, `/clear` and never mentions `statusLine` |

## The transcript is reachable, and still not a viable source

This is the closest thing to a second channel, so the rejection is recorded in full rather than
summarized.

Every hook receives `transcript_path`, and the sessions page explicitly lists reading it as one of
the supported ways to "React to session events". The file is live: in the measured container it was
being appended to continuously, and each assistant entry carries a `usage` object whose
`input_tokens`, `cache_creation_input_tokens` and `cache_read_input_tokens` are exactly the three
addends the status line page says `used_percentage` is computed from. A hook could read the last
such entry and write a snapshot with no status line involved.

It is rejected because the same page disqualifies the parse
(<https://code.claude.com/docs/en/sessions>, read 2026-08-21):

> Each line is a JSON object for a message, tool use, or metadata entry. The entry format is
> internal to Claude Code and changes between versions, so scripts that parse these files directly
> can break on any release.

`transcript_path` is a documented **path**. The bytes behind it are documented as internal and
version-unstable. A capture path built on them would be a zone instrument whose accuracy is
warranted by nothing, and this contract's whole posture is that a consumer is never throttled on
data it cannot trust and a zone is never fabricated. A wrong zone is strictly worse than `unknown`:
`unknown` routes the consumer to its conservative path, while a stale or misread occupancy can read
`smart` on a nearly full window and route heavy work into a degraded context. The failure would
also be silent and version-triggered — it would arrive on a Claude Code release, not on a change to
this plugin.

The plugin therefore does **not** ship a transcript-derived capture path.

## What this means for consumers

- **`unknown` in a session with no configured `statusLine` is the expected steady state.** Report
  it as "no instrument in this environment", never as a broken install, a missing dependency, or a
  reason to ask the operator to fix something.
- **The conservative path is still correct.** Nothing here changes the fail-open rule: `unknown`
  means take the conservative route.
- **Do not synthesize a zone from any other source.** No documented substitute exists, and the two
  reachable near-substitutes — the cumulative OTel counter and the transcript's internal entry
  format — both fail in the direction that produces a confident wrong answer.
- **Cost of the gap.** The instrument is absent exactly where sessions are most disposable, so an
  instrument-driven handoff or fork trigger cannot fire there. A consumer that wants a handoff
  trigger in a cloud or headless session must drive it from something other than a zone reading —
  an explicit operator request, or an observation the consumer makes itself. It must not treat
  `unknown` as evidence of a full window; `unknown` carries no direction.

## Distinguishing structural absence from breakage

Both states print `unknown`, so the discriminator is the writer side, and it is doc-backed:
the status line runs only where a `statusLine` command is configured
(<https://code.claude.com/docs/en/statusline>, read 2026-08-21).

1. Read `statusLine` from every settings scope that can carry it — user `~/.claude/settings.json`,
   project `.claude/settings.json`, local `.claude/settings.local.json`.
2. **No `statusLine` in any scope** → structural. No snapshot can be written for this session by
   any mechanism this plugin ships. `unknown` is correct and final until a status line is
   configured *and* the environment refreshes one.
3. **A `statusLine` is configured but no fresh snapshot exists** → a real defect: wiring, the
   installed shim, or `jq`. Invoke `/context-guard:setup` via the Skill tool with `check` for the
   full diagnosis.

A cloud or headless session lands on branch 2 by default: no `statusLine` is configured, and the
status line is a terminal-interface surface — the page describes it rendering above the footer
badges and reading `COLUMNS` / `LINES` for terminal dimensions. Configuring one there is not a
remediation to offer.

## What would have to change upstream

Any **one** of these would make a cloud- and headless-compatible capture path possible, and each is
a change to Claude Code, not to this plugin:

- **A context field on hook stdin.** The smallest sufficient change: add the `context_window`
  object (or its `used_percentage` alone) to the documented common input fields. Every hook already
  receives `session_id`, so a `PostToolBatch` or `UserPromptSubmit` hook could write the existing
  snapshot shape with no new contract on the reader side.
- **A documented, stable transcript entry schema** — at minimum a versioned, supported shape for
  the per-message `usage` object — which would convert the near-miss above into a real channel.
- **A documented status-line equivalent that runs without a terminal**, or a statement that cloud
  sessions refresh a configured `statusLine`. Neither is documented today.
- **A current-occupancy gauge in the OpenTelemetry metric set**, as opposed to the existing
  cumulative token counter.

Re-check this file against the pages above when Claude Code's hooks or status line reference
changes. The finding is dated, not permanent.
