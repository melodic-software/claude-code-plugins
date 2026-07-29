# Rate-limit guard — reader contract

The consumer-facing contract for the machine-scope rate-limit artifacts this plugin produces.
Writers are the plugin's `scripts/statusline-tee.sh` (proactive window data) and
`hooks/record-rate-limit-stop.sh` (reactive detection records). Readers are loop-lane session
bodies; an installed plugin cannot read a sibling plugin's files at runtime, so **consumers inline
the operable floor below verbatim** and cite this file for provenance only — the inline-floor rule,
and the requirement that the inlined values stay byte-identical across consumers, is owned by the
loop-lane convention (`docs/conventions/loop-lane/README.md` §6 in the marketplace repository).

## Operable floor (consumers inline these values verbatim)

- **Tee file (fixed path):** `~/.claude/rate-limit-guard/rate-limits.json`
- **Pause threshold (fixed):** pause when **either** window reports `used_percentage >= 90`
- **Pause end:** the **tripped** window's `resets_at`; when **both** windows trip, the **later**
  `resets_at`
- **Staleness rule:** a snapshot whose `captured_at` is older than **10 minutes** is stale — treat
  the windows as **unknown** (reactive-only) for that decision; a `resets_at` already latched from a
  fresh snapshot stays valid through the pause (no refresh happens while paused). While paused, a
  consumer **must** arm a session Monitor on the tee file and re-evaluate on every write — the file
  carries **no account-identifier field**, so a write is the only signal that the windows changed
  under you (account switch, another session's refresh).
- **Drain-then-pause:** on a trip, finish in-flight work, stop claiming new work, pause until the
  pause end, and report; a hard stop happens only on explicit user request.

## Tee file shape

One JSON object, rewritten atomically on every statusline refresh (temp file + rename — a reader
never sees torn JSON; the file is **last-writer-wins** across all sessions on the machine):

```json
{
  "captured_at": "2026-07-23T17:41:02Z",
  "session_id": "abc123",
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1784841300 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1785142800 }
  }
}
```

(The example is internally consistent: `1784841300` is 2026-07-23T21:15:00Z — within five hours of
`captured_at` — and `1785142800` is 2026-07-27T09:00:00Z, within the seven-day window.)

- `captured_at` — ISO-8601 UTC write time; always present. Drives the staleness rule.
- `rate_limits` — copied verbatim from the statusline stdin schema
  (<https://code.claude.com/docs/en/statusline>, verified 2026-07-23): `used_percentage` is 0–100,
  `resets_at` is Unix epoch seconds. The key is present **only** when the session observes
  subscription windows; each window may be independently absent.
- Session-distinguishing fields — `session_id`, `session_name`, and any **top-level** field whose key
  **contains** `account`, case-insensitively, are copied through automatically. That is the whole of
  the writer's filter, and it has no else branch: a field nested inside an object
  (`user.account_uuid`), or named anything else (`user`, `identity`, `org`, `seat`), is dropped
  silently. A future account identifier therefore reaches this file unchanged only if it arrives
  top-level and `account`-named; any other shape needs a writer change. Treat these values as
  **untrusted**: `session_name` (and potentially a future account field) is user/AI-influenced, so
  consumers parse them only with a JSON parser and never string-interpolate them into a shell
  command, another interpreter, or a prompt.

## Capability detection (fail-open)

Windows may be unobservable (API-key and enterprise auth carry limits but expose no
`rate_limits`). A consumer classifies its guard mode before every pause decision:

| Observation | Scope | Mode |
|---|---|---|
| Fresh snapshot with plausible `rate_limits` | whole guard | **proactive** — apply the operable floor |
| Tee file absent, stale, or missing `rate_limits` | whole guard | **unknown → reactive-only** |
| Absurd `used_percentage` or `resets_at` | that window | that window **unknown**; the floor still applies to every window still plausible |
| No window plausible | whole guard | **unknown → reactive-only** |

The scope column is load-bearing: only the whole-guard rows drop the guard to reactive-only. Absurd
values fail open, never closed: a `used_percentage` outside 0–100 or non-numeric, or a `resets_at`
that is non-numeric, more than 8 days in the future, or already past by more than the staleness
window, makes **that window** unknown — and each window may be independently absent. Keep applying
the floor to every window still plausible: one absurd window is no reason to ignore a valid window
already at or above 90, and a trip on the only plausible window is still a trip. The consumer never
throttles proactively on data it cannot trust, and never fabricates a pause.

**Reactive-only mode:** no proactive throttling. The consumer reacts to the detection records in
`~/.claude/rate-limit-guard/stop-events.jsonl` (below) and to the rate-limit error text its own
session sees; resume timing comes from that error text where available, otherwise
backoff-and-retry. A later fresh snapshot with plausible windows upgrades the mode back to
proactive.

## Detection records (reactive fallback)

`~/.claude/rate-limit-guard/stop-events.jsonl` — one JSON line per `StopFailure(rate_limit)` event,
appended by the hook:

```json
{"detected_at":"2026-07-23T17:41:02Z","hook_event_name":"StopFailure","matcher":"rate_limit","session_id":"abc123"}
```

The hook is side-effect-only (the harness ignores StopFailure output and exit codes) and the
payload carries no reset or quota data — a record means "a rate limit stopped a turn at this time",
nothing more. The file is bounded (rotated to the newest 100 records past 200).

The contract directory holds one more file: `stop-events.jsonl.lock`, the advisory-lock sibling the
hook's serialized append and rotation use (present wherever `flock` exists). Readers ignore it; it
is part of the seam only in the sense that tooling sweeping the directory should expect it.

## Invariants and boundaries

- **Single-account-per-machine is a known gap.** The tee file is last-writer-wins with no account
  id: a mid-drain login to a second account feeds that account's healthy windows to lanes exhausted
  on the first, and the guard cannot detect it. The loop-lane convention §6 owns the framing and
  records it as a gap rather than as a safe assumption; the account-identity design that resolves
  it — writer-side field, reader-side invalidation of latched state, lane-floor re-audit — is
  `TODO(#1218)`. Locally relevant today, and only this far: the writer already forward-passes a
  top-level key containing `account` (see "Tee file shape"), so an identity field of exactly that
  shape costs no writer change the release one appears. Any other shape — nested, or named anything
  else — is dropped silently and needs a filter change.
- **No shipped Monitor config.** Consumers arm their own session Monitor on the tee file (the
  staleness rule makes this mandatory while paused). The plugin ships no `experimental.monitors`
  entry — Monitors is an experimental Claude Code component, and this plugin takes no dependency on
  one until it stabilizes.
- **Fixed constants.** The tee path and the 90% threshold are contract constants, deliberately not
  configurable: cross-plugin consumers read the documented values, so a per-user override could
  silently split writer and readers. The only `userConfig` is the hook kill switch.

## Consumers

The loop-lane convention's three lanes: `work-items` `work-loop`, `work-items` `attend-queue`, and
`source-control` `babysit-loop`. Each records its guard mode (proactive / reactive / unknown) in its
lane telemetry every cycle, per the convention.
