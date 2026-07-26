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
- **Default percentage bands (over `context_window.used_percentage`, uppers inclusive):**
  `smart` ≤ **50** < `acceptable` ≤ **75** < `dumb`. These shipped defaults apply only when
  `zones.json` is absent or malformed; when the file is present and valid, its bands win (see
  Zones below).
- **Default token bands (over occupancy = `total_input_tokens` + `total_output_tokens`, uppers
  inclusive, selected by window class — see "Occupancy and combination rule"):**
  window class **200000**: `smart` ≤ **100000** < `acceptable` ≤ **160000** < `dumb`;
  window class **1000000**: `smart` ≤ **200000** < `acceptable` ≤ **400000** < `dumb`.
- **Combination rule (verbatim — consumers inline this sentence):** when both shapes are
  computable, the worse zone wins (conservative-min); when only one is computable, it stands
  alone; when neither is, the zone is unknown.
- **Evidence-degraded marker (fixed path, optional):**
  `~/.claude/context-guard/context/<session_id>.compacted` — presence means the session was
  compacted; treat it as evidence-degraded regardless of zone.
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
- Treat all values as **untrusted data**: parse with a JSON parser; validate any value against its
  documented format BEFORE handing it to a lenient parser (the bundled resolver format-gates
  `captured_at` to strict ISO-8601 before date parsing, and requires the embedded `session_id` to
  equal the requested one); never pass snapshot values to anything that executes them (`eval`,
  `sh -c`, a string-built jq program) and never string-interpolate them into a prompt.
- **No writer authentication exists.** The directory is owner-only where POSIX modes work
  (`chmod 700`, best-effort); on filesystems without them (e.g. Windows ACL volumes under Git
  Bash) other local users could read or forge snapshots. A forged-but-well-formed snapshot is
  indistinguishable from a real one; the zone is a ROUTING hint, so the worst case of forgery is
  a wrong dispatch decision, never an egress or execution decision — consumers must not attach
  security decisions to zone words.

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

## Occupancy and combination rule

The contract carries TWO zone shapes because the two underlying measures answer different
questions — never equate them without normalizing:

- **Percentage shape** — `context_window.used_percentage` against the percentage bands. Upstream
  computes it from **input tokens only** (`input_tokens + cache_creation_input_tokens +
  cache_read_input_tokens`, no output — statusline doc, verified 2026-07-26). It answers
  *distance to compaction*, because compaction thresholds key off the same accounting.
- **Token shape** — **occupancy**, defined as `total_input_tokens + total_output_tokens`, against
  the window-class token bands. Occupancy counts both directions because both occupy the window,
  and the degradation evidence (Chroma context-rot report; Anthropic system-card fixed-point
  evals) tracks **absolute tokens in context, not window fraction**. It answers *distance to
  quality loss*. That is also why the token bands are absolute numbers selected by window class
  rather than percentages: 50% of a 1M window is a materially different cognitive state than 50%
  of a 200k window.

**Window-class selection:** use the band row whose class key is the **largest one ≤
`context_window_size`**. A window smaller than every configured class has no row — the token
shape is then not computable (never borrow a larger class's looser bands).

**Combination rule (consumers inline this sentence verbatim):** when both shapes are computable,
the worse zone wins (conservative-min); when only one is computable, it stands alone; when
neither is, the zone is unknown. Rationale: the two shapes disagree exactly when one measure has
information the other lacks (a deep-but-cache-heavy window, a small window near compaction), and
a routing hint must degrade toward caution, never toward optimism.

**Version floor / plausibility guard:** `total_input_tokens` / `total_output_tokens` mean
*current context occupancy* only since Claude Code **2.1.132** — before that they were cumulative
session totals ("Before v2.1.132 these were cumulative session totals", statusline doc, verified
2026-07-26), which would misfire the token bands badly. The snapshot carries no CLI version, so
readers apply the observable guard instead: **occupancy greater than `context_window_size` marks
the token shape not-computable** (cumulative semantics or corrupt data), leaving the percentage
shape to stand alone. The bundled resolver implements exactly this.

**Percentage-key retirement trigger:** the percentage vocabulary is retained because it answers a
question the token shape cannot (distance to compaction) and because shipped consumers inline its
floor today. It retires when no shipped consumer inlines the percentage floor any longer —
recorded here so back-compat alone never makes the second vocabulary permanent.

**Band provenance:** all shipped band numbers are **declared judgment defaults with named
anchors** (issue #1475 carries the full provenance table), not benchmark-derived constants. The
1M row's anchor is a named-staff informal range (self-hedged "highly task-dependent"); the 200k
row is declared judgment near — but deliberately below — practitioner folklore values. Both rows
carry equally low confidence; `zones.json` is the correction path, and the numeric agreement of
the 200k row's percentage translation with the shipped 50/75 percentage defaults is coincidence,
not validation.

## Zone-crossing hooks (first shipped consumer)

Since 0.4.0 the plugin itself ships hooks over its own seam — the first shipped consumer:

- **Advisory injection** (`PostToolBatch` + `UserPromptSubmit`): once per transition into a worse
  zone, inject continuation guidance (a minimal generic continuation tree plus a presence-gated
  pointer to `session-flow:workflow`'s router). Silent while the zone is unchanged, improving, or
  `unknown`.
- **Blocking gate** (`PreToolUse`, only when the `zone_hook_mode` userConfig option is
  `blocking`): denies new `Write|Edit|NotebookEdit|Agent|Workflow` calls on a **fresh dumb-zone
  snapshot** past a small grace budget. Fail-open on `unknown`; handoff-path writes, read-only
  tools, Bash, and Skill invocations are never gated, so a durable handoff is always writable.
- **PostCompact marker**: writes the evidence-degraded marker file (below).

Hook state (last-seen zone, gate counters) lives under `${CLAUDE_PLUGIN_DATA}` — plugin-private,
NOT part of this contract. The hooks consume the seam through the same resolver consumers
re-implement; they add no new snapshot semantics.

## Evidence-degraded marker

`~/.claude/context-guard/context/<session_id>.compacted` — written by the PostCompact hook,
last-write-wins per session:

```json
{ "compacted_at": "2026-07-26T12:00:00Z", "trigger": "auto", "hook_event_name": "PostCompact" }
```

`trigger` is `manual` | `auto` | `unknown`. **Presence alone is the signal**: a consumer that
finds the marker treats the session as evidence-degraded regardless of a green zone (see the next
section for why). Consumers should not gate on `compacted_at` freshness — compaction's evidence
loss does not expire with time in the same session. The marker is part of this contract's seam
(fixed path, same character-class and trust rules as snapshots); it closes the documented gap
that the snapshot alone cannot reveal compaction.

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
  "acceptable_max_used_percentage": 75,
  "token_bands": {
    "200000": { "smart_max_tokens": 100000, "acceptable_max_tokens": 160000 },
    "1000000": { "smart_max_tokens": 200000, "acceptable_max_tokens": 400000 }
  }
}
```

Validity is **per shape, independently**:

- **Percentage keys:** both values numeric, `0 < smart_max < acceptable_max ≤ 100`. Malformed
  (unparsable file, non-numeric, inverted, out of range) → shipped percentage defaults with a
  visible stderr notice from the resolver (unchanged v1 behavior, including when the keys are
  simply absent from an otherwise-parsable file).
- **`token_bands` (optional):** when present, an object whose every key is a decimal window-class
  string and every value carries numeric `smart_max_tokens` and `acceptable_max_tokens` with
  `0 < smart < acceptable ≤ class`. Malformed as a whole → shipped token bands with its own
  visible stderr notice. **Absent is zero-config** (shipped token bands, silently) — a v1
  percentage-only file keeps working unchanged.

Unrecognized keys are permitted and preserved (the setup skill's `apply` seeds/refreshes this
file idempotently; the resolver only reads it).

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
  session Monitor on their snapshot path. The plugin ships no `experimental.monitors` entry —
  Monitors is an experimental Claude Code component, and this plugin takes no dependency on one
  until it stabilizes.
- **Fixed staleness constant.** The 10-minute value is a contract constant, deliberately not
  configurable: cross-plugin consumers inline the documented value, so a per-user override would
  silently split writer and readers. Band NUMBERS are the one tunable — via `zones.json`, which
  display and consumers share.

## Consumers

- The plugin's own zone-crossing hooks (first shipped consumer — see "Zone-crossing hooks").
- The `plugin-quality` audit skill (context-gate: zone-informed dispatch and evidence-flush
  decisions, conservative on `unknown`). Its inlined floor values are drift-checked against this
  file by its co-located `zones-inline-drift.test.sh` lane, which runs in the repo's plugin-gate
  CI job.
