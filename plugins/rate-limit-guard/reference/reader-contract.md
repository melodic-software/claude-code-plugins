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
- **Staleness rule:** a snapshot whose `captured_at` is older than **10 minutes** is stale. Treat
  the windows as **unknown** (reactive-only) for that decision; a `resets_at` already latched from a
  fresh snapshot stays valid through the pause (no refresh happens while paused). While paused, a
  consumer **must** arm a session Monitor on the tee file and re-evaluate on every write: the file
  carries **no account-identifier field**, so a write is the only signal that the windows changed
  under you (account switch, another session's refresh).
- **Drain-then-pause:** on a trip, finish in-flight work, stop claiming new work, pause until the
  pause end, and report; a hard stop happens only on explicit user request.

## Tee file shape

One JSON object, rewritten atomically on a **drain cadence** rather than on every refresh (temp file

- rename — a reader never sees torn JSON; the file is **last-writer-wins** across all sessions on the
  machine). Each refresh records its observation to a private per-session spool file with no external
  process at all, and one elected refresh per cadence flushes the batch into this file, so the snapshot
  trails the newest refresh on the machine by **at most 30 seconds**. That is well inside the
  10-minute staleness budget below, and the operable floor values are unchanged. `captured_at` is the
  **observation time of the record the drain chose** — when those windows were seen — not the time the
  file was written:

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

- `captured_at` — ISO-8601 UTC **observation** time of the chosen record; always present. Drives the
  staleness rule. It can trail the file's mtime by up to the drain cadence (30 s), which is why the
  rule is written against this field and never against the file's modification time.
- `rate_limits` — copied verbatim from the statusline stdin schema
  (<https://code.claude.com/docs/en/statusline>, verified 2026-08-10): `used_percentage` is 0–100,
  `resets_at` is Unix epoch seconds. The key is present **only** when the session observes
  subscription windows; each window may be independently absent.
- Session-distinguishing fields — `session_id`, `session_name`, and any **top-level** key whose name
  **contains** `account` (case-insensitive) are copied through automatically. The writer selects on
  the **top-level key name only**, and a selected key carries its **whole value** across, nested
  objects included: `account_info: {uuid, display_name}` arrives complete. A key that does not match
  is dropped with no diagnostic — `user`, `identity`, `org`, and `seat` all vanish silently, and so
  does an `account_uuid` buried inside a non-matching object such as `user`, because nothing at the
  top level matched. A future account identifier therefore arrives without a writer change only when
  its own top-level key name contains `account`; every other shape needs one. Treat these values as
  **untrusted**: `session_name`, and any future account field — which may be an **object of
  arbitrary strings**, not just a scalar — are user/AI-influenced, so consumers parse them only with
  a JSON parser and never string-interpolate them into a shell command, another interpreter, or a
  prompt.

## Capability detection (fail-open)

Windows may be unobservable (API-key and enterprise auth carry limits but expose no
`rate_limits`). A consumer classifies its guard mode before every pause decision:

| Observation                                      | Scope       | Mode                                                                             |
| ------------------------------------------------ | ----------- | -------------------------------------------------------------------------------- |
| Fresh snapshot with plausible `rate_limits`      | whole guard | **proactive** — apply the operable floor                                         |
| Tee file absent, stale, or missing `rate_limits` | whole guard | **unknown → reactive-only**                                                      |
| Absurd `used_percentage` or `resets_at`          | that window | that window **unknown**; the floor still applies to every window still plausible |
| No window plausible                              | whole guard | **unknown → reactive-only**                                                      |

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

## Cloud / remote sessions (expected degraded mode)

The tee path and the StopFailure detection file are **machine-local and statusline-driven**. Cloud
and remote-session containers (Claude Code on the web, remote-control targets, and similar
ephemeral environments) typically have **no statusline wiring** and an **ephemeral filesystem**:
`~/.claude/rate-limit-guard/` is absent, so there is no fresh snapshot and usually no
`stop-events.jsonl` either. Verified empirically in a live cloud session (2026-08-15).

That observation is **not a misconfiguration**. Under the capability-detection table above it
classifies as **unknown → reactive-only**. Consumers must not invent window percentages, pause
ends, or "healthy headroom" from the absence of the tee — fabricating proactive state is exactly
what fail-open forbids.

**What a cloud / remote consumer may use as signal (reactive only):**

1. **This session's own rate-limit errors** — API / harness text that names a rate limit or carries
   a reset time. Prefer the reset time in that text when present; otherwise backoff-and-retry.
2. **Sibling automation 429s visible to the session** — machine-readable infra comments or CI
   annotations on PRs/issues this session is already reading (for example review-lane comments that
   classify `api_error_status: 429` as `rate-limit`). Treat a live cluster of sibling 429s as thin
   headroom: shrink concurrency further; restore width only after those signals stop, never on a
   guessed recovery.
3. **`stop-events.jsonl` when present** — same read cadence as the reactive fallback below. In a
   typical cloud container the file is absent; absence is not evidence of healthy windows.

**Orchestration fallback when headroom is unobservable.** Sessions that size fan-out width from
rate-limit headroom (notably `session-flow`'s `/session-flow:orchestrate` imperative 7) treat
unobservable headroom as **thin by default**: start at a small conservative concurrent-worker cap,
prefer shorter waves over a wide tree, and scale only on the reactive signals above — never on the
missing tee. The orchestrate skill owns the imperative wording; this contract owns the
classification that makes the fallback mandatory rather than optional.

**Documented residual (not closed here):** a live statusline (or equivalent) producer that would
write the tee inside cloud / remote containers does not exist in those environments today. Shipping
that producer — fleet `cloud-environment` wiring, a synced snapshot, or a harness/API exposure —
is the residual path to proactive mode in cloud. Until it lands, unknown → reactive-only plus the
orchestration fallback above is the complete honest contract. Do not open a tracking issue solely
to restate this residual; the residual is this paragraph.

## Detection records (reactive fallback)

`~/.claude/rate-limit-guard/stop-events.jsonl` — one JSON line per `StopFailure(rate_limit)` event,
appended by the hook:

```json
{
  "detected_at": "2026-07-23T17:41:02Z",
  "hook_event_name": "StopFailure",
  "matcher": "rate_limit",
  "session_id": "abc123"
}
```

The hook is side-effect-only (the harness ignores StopFailure output and exit codes) and the
payload carries no reset or quota data — a record means "a rate limit stopped a turn at this time",
nothing more. The file is bounded (rotated to the newest 100 records past 200).

Read cadence: a reactive-only consumer reads the file on entering reactive-only mode and again
before each new work claim. The recency baseline starts at the consumer's own start time — records
older than that are history even on the first read — and each later resume attempt advances it.
Records with `detected_at` newer than the baseline are live signal; older ones are history and
never justify a new pause on their own. The baseline is per-consumer and in-memory; nothing
persists it, and a fresh consumer deliberately ignores prior sessions' records.

The contract directory holds two more shapes, neither of which readers consume, listed so tooling
sweeping the directory expects them:

- `stop-events.jsonl.lock` — the advisory-lock sibling the hook's serialized append and rotation use
  (present wherever `flock` exists).
- `spool/` — the tee's per-session write-ahead spool, owner-only by inheritance from the contract
  directory. `spool/<session>.json` holds ONE line: the newest observation that session recorded,
  overwritten in place each refresh (never appended, so no two writers ever share a file). The name
  is a shard key derived from `session_id` and reduced to `misc` unless it matches
  `^[A-Za-z0-9._-]{1,64}$` without a leading dot — it is **never** trusted as a path. `spool/.last-drain`
  holds the epoch seconds of the last flush and is what elects the next draining refresh; a stale
  `spool/.drain.lock` directory can appear if a drain is killed and is stolen after two minutes.
  Records older than 15 minutes are swept by the next drain. Readers consume none of this: the
  contract file above is still the only proactive surface.
- `.tee-disabled` — written by a drain that read `rate_limit_guard_enabled: false`, holding the epoch
  seconds at which it was written. While it is present and younger than the recheck interval the
  refreshes stop recording entirely; when it ages out the next drain re-reads the real setting and
  removes the marker, so re-enabling the plugin recovers without a restart.
- `.rate-limits.json.tmp.<pid>.<random>` — the tee's atomic-write staging file. Normally it exists
  for well under a second between write and rename. It can outlive its writer: Claude Code
  [cancels an in-flight statusline script](https://code.claude.com/docs/en/statusline) when a new
  update arrives, and a cancellation inside that window leaves the file behind. The tee reclaims its
  own on exit and on a catch-able signal, and sweeps siblings older than a minute on the next
  refresh, which is what recovers from a SIGKILL, a crash, or power loss. A cleanup tool should
  leave these alone: one may belong to a live concurrent session, and the tee reclaims them itself.

## Invariants and boundaries

- **Single-account-per-machine is a known gap.** The tee file is last-writer-wins with no account
  id: a mid-drain login to a second account feeds that account's healthy windows to lanes exhausted
  on the first, and the guard cannot detect it. The loop-lane convention §6 owns the framing and
  records it as a gap rather than as a safe assumption; the account-identity design that resolves
  it — writer-side field, reader-side invalidation of latched state, lane-floor re-audit — is
  `TODO(#1218)`. Locally relevant today, and only this far: the writer already forward-passes an
  account-matching key under the exact rule "Tee file shape" states, so an identity field of that
  shape costs no writer change the release one appears — and every other shape costs one.
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
