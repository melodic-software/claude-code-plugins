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
    "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
  }
}
```

- `captured_at` — ISO-8601 UTC write time; always present. Drives the staleness rule.
- `rate_limits` — copied verbatim from the statusline stdin schema
  (<https://code.claude.com/docs/en/statusline>, verified 2026-07-23): `used_percentage` is 0–100,
  `resets_at` is Unix epoch seconds. The key is present **only** when the session observes
  subscription windows; each window may be independently absent.
- Session-distinguishing fields — `session_id`, `session_name`, and any future top-level field whose
  key matches `account` (case-insensitive) are copied through automatically, so the release that
  adds an account identifier upgrades this file without a plugin change. Treat these values as
  **untrusted**: `session_name` (and potentially a future account field) is user/AI-influenced, so
  consumers parse them only with a JSON parser and never string-interpolate them into a shell
  command, another interpreter, or a prompt.

## Capability detection (fail-open)

Windows may be unobservable (API-key and enterprise auth carry limits but expose no
`rate_limits`). A consumer classifies its guard mode before every pause decision:

| Observation | Mode |
|---|---|
| Fresh snapshot with plausible `rate_limits` | **proactive** — apply the operable floor |
| Tee file absent, stale, missing `rate_limits`, or absurd values | **unknown → reactive-only** |

Absurd values fail open, never closed: a `used_percentage` outside 0–100 or non-numeric, or a
`resets_at` that is non-numeric, more than 8 days in the future, or already past by more than the
staleness window, makes that window **unknown** — the consumer never throttles proactively on data
it cannot trust, and never fabricates a pause.

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

## Invariants and boundaries

- **Single-account-per-machine.** The tee file is last-writer-wins with no account id: a mid-drain
  login to a second account feeds that account's healthy windows to lanes exhausted on the first.
  The guard cannot detect this; operation assumes one account per machine (owned by the loop-lane
  convention §6).
- **No shipped Monitor config.** Consumers arm their own session Monitor on the tee file (the
  staleness rule makes this mandatory while paused). The plugin ships no `experimental.monitors`
  entry — the fleet stance on the experimental Monitors component is Wait
  (`docs/PLUGIN-PHILOSOPHY.md`, Component stances).
- **Fixed constants.** The tee path and the 90% threshold are contract constants, deliberately not
  configurable: cross-plugin consumers read the documented values, so a per-user override could
  silently split writer and readers. The only `userConfig` is the hook kill switch.

## Consumers

The loop-lane convention's three lanes: `work-items` `work-loop`, `work-items` `attend-queue`, and
`source-control` `babysit-loop`. Each records its guard mode (proactive / reactive / unknown) in its
lane telemetry every cycle, per the convention.
