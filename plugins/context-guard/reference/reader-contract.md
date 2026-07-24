# Context guard — reader contract

The consumer-facing contract for the per-session context-window snapshots this plugin produces.
The writer is the plugin's `scripts/statusline-tee.sh`; `scripts/context-zone.sh` is the bundled
resolver over the same data. Readers are sibling-plugin sessions (e.g. an audit skill deciding
whether to dispatch deep work to a fresh subagent). An installed plugin cannot read a sibling
plugin's files at runtime, so **consumers inline the operable floor below verbatim** and cite this
file for provenance only.

**Inline-floor ownership:** THIS file owns the operable floor — the snapshot path pattern, the
staleness value, and the default zone bands. Inlined copies in consumers must stay
**byte-identical** to the values printed here; a consumer lane carries a drift check that
grep-matches its inlined values against this file.

## Operable floor (consumers inline these values verbatim)

- **Snapshot path pattern (fixed):** `~/.claude/context-guard/context/<session_id>.json`
- **Zones file (fixed path, optional):** `~/.claude/context-guard/zones.json`
- **Staleness rule:** a snapshot whose `captured_at` is older than **10 minutes** is stale — treat
  the zone as **unknown** for that decision.
- **Default zone bands (over `context_window.used_percentage`, uppers inclusive):**
  `smart` ≤ **50** < `acceptable` ≤ **75** < `dumb`. These shipped defaults apply only when
  `zones.json` is absent or malformed; when the file is present and valid, its bands win (see
  Zones below).
- **Zone vocabulary:** `smart` / `acceptable` / `dumb` / `unknown` — `unknown` is the conservative
  word; consumers treat it as "assume degraded".

## Snapshot file shape

One JSON object per session, rewritten atomically on every statusline refresh (temp file + rename —
a reader never sees torn JSON). Files are **per-session**, NOT machine-scope last-writer-wins:
concurrent sessions each own the file named by their `session_id`.

```json
{
  "captured_at": "2026-07-24T05:32:48Z",
  "session_id": "abc123",
  "context_window": {
    "total_input_tokens": 15500,
    "total_output_tokens": 1200,
    "context_window_size": 200000,
    "used_percentage": 8,
    "remaining_percentage": 92,
    "current_usage": {
      "input_tokens": 8500,
      "output_tokens": 1200,
      "cache_creation_input_tokens": 5000,
      "cache_read_input_tokens": 2000
    }
  }
}
```

- `captured_at` — ISO-8601 UTC write time; always present. Drives the staleness rule.
- `session_id` — always present (the tee refuses to write without one); also the filename stem,
  sanitized to `[A-Za-z0-9_-]`.
- `context_window` — copied **verbatim** from the statusline stdin schema
  (<https://code.claude.com/docs/en/statusline>, verified 2026-07-24), so upstream field additions
  flow through without a plugin change. The key is absent when the session's statusline payload
  carried none. Null states are upstream-documented and normal: `used_percentage` /
  `remaining_percentage` may be `null` early in a session; `current_usage` is `null` before the
  first API call **and again immediately after `/compact`** until the next response repopulates it.
- Treat all values as **untrusted data**: parse only with a JSON parser; never string-interpolate
  snapshot values into a shell command, another interpreter, or a prompt.

## Capability detection (fail-open)

A consumer classifies before every zone-informed decision:

| Observation | Zone |
|---|---|
| Fresh snapshot, numeric `used_percentage` 0–100, non-null `current_usage` | resolve bands normally |
| Snapshot absent, stale, or unparsable | **unknown** |
| `used_percentage` null / missing / non-numeric / outside 0–100 | **unknown** |
| `current_usage` null or missing (early-session or post-`/compact` state) | **unknown** |
| jq (or equivalent JSON parsing) unavailable to the consumer | **unknown** |

Absurd values fail open, never closed: the consumer never skips its conservative path on data it
cannot trust, and never fabricates a zone. `unknown` always means "take the conservative route".

## Zone is NOT a compaction indicator

A compacted session's `used_percentage` **resets downward** while the evidence in its
conversational context is already gone. A consumer that knows its session was compacted (or
summarized by the harness) must treat the session as **evidence-degraded regardless of zone** —
including a green `smart` reading. The snapshot cannot tell you compaction happened; only the
session itself can know.

**No official auto-compaction threshold exists to ground the bands on.** Verified 2026-07-23
(how-Claude-Code-works, context-window, settings `autoCompactEnabled`, costs pages) and re-verified
2026-07-24 (costs + statusline pages): the docs say only that compaction triggers "when approaching
context limits". The empirical check (2026-07-24, execution session): no auto-compact event exists
in the producing machine's entire transcript history — the largest session ran to 308k total input
tokens uncompacted on a 1M-class window — so the shipped bands are **declared judgment defaults**
with a declared margin (if compaction triggers at ≥ 90% as its phrasing implies, the dumb band
leads it by ≥ 15 points), not doc-derived constants. `zones.json` is the correction path if
compaction is ever observed earlier.

Two adjacent caveats, same fetch: the doc warns the statusline percentage "may differ from
`/context` output due to when each is calculated" — the value is as-of the last API response, not
the next request; and with `autoCompactEnabled: false` no compaction ever fires (the session hard
-stops at the window instead), which makes the dumb band the *only* tripwire — strictly more
load-bearing, never less.

## Zones (machine-scope tuning, optional)

`~/.claude/context-guard/zones.json` — the single source of truth for band tuning on a machine.
The operator's own statusline display MAY read the same file, which eliminates band drift between
what the human sees and what consumers decide on. Zones say *where you are*; consumers decide
*what to do*.

```json
{
  "smart_max_used_percentage": 50,
  "acceptable_max_used_percentage": 75
}
```

Validity: both values numeric, `0 < smart_max < acceptable_max ≤ 100`. A malformed file (unparsable,
non-numeric, inverted, out of range) falls back to the shipped defaults with a visible stderr
notice from the resolver. Unrecognized keys are permitted and preserved (the setup skill's `apply`
seeds/refreshes this file idempotently; the resolver only reads it).

**Consumers read `zones.json` directly** (it is a data seam): under plugin cache isolation a
consumer cannot invoke this plugin's `context-zone.sh`, so it re-implements the band lookup —
file present and valid → its bands; absent or malformed → the inlined default bands above. The
byte-identity rule covers the inlined defaults only.

Resolver invocation (for same-plugin or path-provisioned callers):

```bash
bash "<plugin-root>/scripts/context-zone.sh" <session_id>   # prints one zone word
```

## Session-id discovery (how a consumer learns its own id)

A skill learns its session id via the **`${CLAUDE_SESSION_ID}` substitution** in skill markdown
content (<https://code.claude.com/docs/en/skills>, substitution table, verified 2026-07-24). The
skill body interpolates it into the snapshot path directly.

**Fallback:** when the substitution is unavailable (older Claude Code, non-skill context, or the
literal string `${CLAUDE_SESSION_ID}` survives unexpanded), the consumer must NOT guess a session
id — it takes the **unknown/conservative path** exactly as if the snapshot were absent.

## Idle sessions

The statusline only refreshes on activity: a live-but-idle session's snapshot goes stale by the
10-minute rule and resolves `unknown` until the next interaction refreshes it. That is correct
fail-open behavior, not a bug — an idle session asking for a zone gets a fresh snapshot within one
statusline refresh of waking. The writer's stale-file pruning cutoff (14 days) is deliberately far
above the staleness window, so idle sessions' files are never deleted out from under them.

## Invariants and boundaries

- **Per-session semantics.** One file per session id; no cross-session last-writer-wins collapse.
  Concurrent sessions never contend on the same target (atomic rename protects same-session
  refresh races).
- **Fixed paths, deliberately outside `${CLAUDE_PLUGIN_DATA}`.** The contract directory
  `~/.claude/context-guard/` is a documented cross-plugin artifact seam: sibling-plugin sessions
  read it by the documented path. `${CLAUDE_PLUGIN_DATA}` resolves per-plugin-identity and would
  hide the seam from every consumer.
- **No shipped Monitor config.** Consumers that want write-triggered re-evaluation arm their own
  session Monitor on their snapshot path. The plugin ships no `experimental.monitors` entry — the
  fleet stance on the experimental Monitors component is Wait (`docs/PLUGIN-PHILOSOPHY.md`,
  Component stances).
- **Fixed staleness constant.** The 10-minute value is a contract constant, deliberately not
  configurable: cross-plugin consumers inline the documented value, so a per-user override would
  silently split writer and readers. Band NUMBERS are the one tunable — via `zones.json`, which
  display and consumers share.

## Consumers

First consumer: the `plugin-quality` audit skill (context-gate: zone-informed dispatch and
evidence-flush decisions, conservative on `unknown`). Its inlined floor values are drift-checked
against this file in its own lane.
