# Rate-limit guard reader contract

The consumer-facing contract for the machine-scope rate-limit artifacts this plugin produces.
Writers are the plugin's hooks module, `hooks/register.tsx`, which writes the proactive window data
through `lib/write-snapshot.mjs` in interactive and headless (`-p`, `--bg`, `/loop`) sessions
alike, and `hooks/record-rate-limit-stop.sh` (reactive detection records). The module needs Claude
Code 2.1.287 or later and runs only where mods are on. Readers are loop-lane session
bodies; an installed plugin cannot read a sibling plugin's files at runtime, so **consumers inline
the operable floor below verbatim** and cite this file for provenance only. The inline-floor rule,
and the requirement that the inlined values stay byte-identical across consumers, is owned by the
loop-lane convention (`docs/conventions/loop-lane/README.md` §6 in the marketplace repository).

**Recheck trigger:** re-verify the `rate_limits` source under "Tee file shape" below if the
`SessionRateLimit` entries `$.session.usage()` returns change their `kind`, `percentUsed` or
`resetsAt` fields (the doc comments in the `claude-code/index.d.ts` types Claude Code writes for its
build, see
[create: get the types for your build](https://code.claude.com/docs/en/plugins/mods/create#get-the-types-for-your-build),
as of 2026-10-03, Claude Code 2.1.288); re-verify the cloud/remote-session observation under
"Cloud / remote sessions" below if a persistent `~/.claude/rate-limit-guard/` filesystem ships
inside cloud or remote-session containers, the producer the "Documented residual" paragraph below
names as the path to proactive mode there; and re-verify the `account` field's source under "Tee
file shape" below, and the
consumer read in the floor's "Account switch" bullet, if `.oauthAccount.emailAddress` moves or is
renamed in `~/.claude.json`. That key is **internal CLI state**, not a documented surface: nothing
upstream promises it, so the writer treats a missing or unrecognized value as "cannot attribute"
and this contract expects the field to be absent whenever it does, and a reader that cannot read it
keeps its latch.

## Operable floor (consumers inline these values verbatim)

- **Tee file (fixed path):** `~/.claude/rate-limit-guard/rate-limits.json`
- **Pause threshold (fixed):** pause when **either** window reports `used_percentage >= 95`
- **Pause end:** the **tripped** window's `resets_at`; when **both** windows trip, the **later**
  `resets_at`
- **Staleness rule:** a snapshot whose `captured_at` is older than **10 minutes** is stale. Treat
  the windows as **unknown** (reactive-only) for that decision; a `resets_at` already latched from a
  fresh snapshot stays valid through the pause unless the account changes (see **Account switch**;
  no refresh happens while paused). While paused, a consumer **must** arm a session Monitor on the
  tee file and re-evaluate on every write: the file carries an **`account.email` field when the
  writer could attribute the observation**, so a write is still the signal that the windows changed
  under you (account switch, another session's refresh).
- **Drain-then-pause:** on a trip, finish in-flight work, stop claiming new work, pause until the
  pause end, and report; a hard stop happens only on explicit user request.
- **Account switch:** while paused, a consumer **MUST** read `.oauthAccount.emailAddress` directly
  from `${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json`, never via the tee: a machine running only
  headless sessions never refreshes the tee, so a switch would go unseen. At pause entry, record the
  **latched account** as the `account.email` of the snapshot that tripped, not the account
  `.claude.json` names now: that snapshot can be up to 10 minutes old and may describe an account
  the operator has since left. A snapshot with no `account.email` leaves the entry **unattributed**:
  with no latched account there is no switch to detect. Read `.claude.json` at pause entry and on
  every re-evaluation (each Monitor tick and each wake). When it differs from the latched account,
  re-evaluate at once against the new account's windows, taken from a fresh tee snapshot whose
  `account.email` equals the new account: below 95, drop the latched pause and resume; at or above
  95, keep pausing and re-latch the pause end and the latched account against the new account's
  `resets_at`; with no fresh or attributable snapshot, treat the windows as **unknown**, drop the
  latch, and fall back to reactive-only. An unreadable, absent, or malformed state file, or a
  missing key, means **cannot attribute**: keep the existing latch, never a spurious drop. Never
  print, log, or interpolate the email or the state file (`.claude.json` holds account state); parse
  it with a JSON parser only and treat the value as untrusted.

## Tee file shape

"Tee file" is this contract's name for the snapshot file the module writes; the floor and its
consumers use that name. One JSON object, replaced atomically (temp file + rename, so a reader
never sees torn JSON; the file is **last-writer-wins** across all sessions on the machine). The module decides in memory
whether to write, from main-thread tool results, each measurement after a turn, a 60-second timer
that runs only while a turn runs, and the session's end. A window that moves a whole point, appears,
leaves, or resets is written at once. Otherwise the module and the helper keep to a machine-wide
floor of **one write per 300 seconds**, checked against the `captured_at` on disk under the
helper's lock, after which an unchanged reading is written again. The floor is half the 10-minute
staleness budget below, so a fresh-but-unmoving snapshot never approaches stale, and the operable
floor values are unchanged. The module never writes from a turn a task notification started (a
paused lane's own Monitor tick). `captured_at` is the time the module wrote the reading:

```json
{
  "captured_at": "2026-07-23T17:41:02Z",
  "session_id": "abc123",
  "account": { "email": "lane@example.com" },
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1784841300 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1785142800 }
  }
}
```

(The example is internally consistent: `1784841300` is 2026-07-23T21:15:00Z, within five hours of
`captured_at`, and `1785142800` is 2026-07-27T09:00:00Z, within the seven-day window.)

- `captured_at`: ISO-8601 UTC time of the write, to the second; always present. Drives the
  staleness rule. An unchanged reading can leave it, and the file, untouched for up to the 300 s
  floor, which is why the rule is written against this field and never against the file's
  modification time. The helper never replaces a file with an older `captured_at` unless the file's
  is more than 300 s later than the body's (an implausible clock).
- `rate_limits`: the `five_hour` and `seven_day` entries of the module's latest reading,
  `$.session.usage()` (see the recheck trigger at the top of this file): `used_percentage` is
  0–100, `resets_at` is Unix epoch seconds. The key is present **only** when the session observes
  subscription windows; each window may be independently absent, and a window whose reset time has
  passed is left out. A body without the key (a windowless session) is written only when the file
  on disk has no `rate_limits` either, so it never replaces a file that has windows. No other
  window is written: a gateway's `spend_limit` and any further window the reading reports reach
  Claude only through the module's `mcp__rate-limit-guard__status` tool.
- `session_id`: the writing session's id. After `/branch` the file takes the new session's id at
  its first write. The file carries no `session_name` and no other session field.
- `account`: `{"email": "<address>"}`, the account whose windows this snapshot describes. Present
  only when the writer could **attribute** the observation. The value is Claude Code's own
  `.oauthAccount.emailAddress`, read from `${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json` (see the
  recheck trigger at the top of this file: that key is internal CLI state).
  **Absence is normal and never means "one account on this machine".** The module reads the state
  file at each API response and again at the write, and writes the key only when both reads
  return the same email-shaped value. It omits the key rather than risk mislabeling when:
  - the state file is absent or unreadable, or holds no email-shaped value, at either read;
  - the account changed between the last API response and the write, which means an account
    switch may have happened between the observation and the write; the windows are still
    written, only the identity is withheld;
  - the session has seen no API response yet.

  A reader that needs identity therefore treats a missing `account.email` as **unattributed**, never
  as a match, and a snapshot whose `account.email` differs from the account a consumer is running
  under describes **someone else's windows**. Treat the value as **untrusted**: it is
  user-influenced, so consumers parse it only with a JSON parser and never string-interpolate it
  into a shell command, another interpreter, or a prompt. The writer validates only enough to keep
  its own JSON well-formed, judging the value's **codepoints** (3–254 of them, none below 32 and
  none equal to 34, 92, or 127, at least one `@`). That is a shape whitelist, not an assertion that
  the address is real or that it belongs to the reader.

## Capability detection (fail-open)

Windows may be unobservable (API-key and enterprise auth carry limits but expose no
`rate_limits`). A consumer classifies its guard mode before every pause decision:

| Observation                                      | Scope       | Mode                                                                             |
| ------------------------------------------------ | ----------- | -------------------------------------------------------------------------------- |
| Fresh snapshot with plausible `rate_limits`      | whole guard | **proactive**: apply the operable floor                                          |
| Tee file absent, stale, or missing `rate_limits` | whole guard | **unknown → reactive-only**                                                      |
| Absurd `used_percentage` or `resets_at`          | that window | that window **unknown**; the floor still applies to every window still plausible |
| No window plausible                              | whole guard | **unknown → reactive-only**                                                      |

The scope column decides how far a failure reaches: only the whole-guard rows drop the guard to
reactive-only. Absurd
values fail open, never closed: a `used_percentage` outside 0–100 or non-numeric, or a `resets_at`
that is non-numeric, more than 8 days in the future, or already past by more than the staleness
window, makes **that window** unknown, and each window may be independently absent. Keep applying
the floor to every window still plausible: one absurd window is no reason to ignore a valid window
already at or above 95, and a trip on the only plausible window is still a trip. The consumer never
throttles proactively on data it cannot trust, and never fabricates a pause.

**Reactive-only mode:** no proactive throttling. The consumer reacts to the detection records in
`~/.claude/rate-limit-guard/stop-events.jsonl` (below) and to the rate-limit error text its own
session sees; resume timing comes from that error text where available, otherwise
backoff-and-retry. A later fresh snapshot with plausible windows upgrades the mode back to
proactive. A machine where no active session runs the module (mods off, Claude Code older than
2.1.287, or the plugin disabled in every active project) gets no fresh snapshot, which classifies
the same way.

## Cloud / remote sessions (expected degraded mode)

The tee path and the StopFailure detection file are **machine-local**: each session writes them on
the machine it runs on. Cloud and remote-session containers (Claude Code on the web,
remote-control targets, and similar ephemeral environments) have an **ephemeral filesystem**:
`~/.claude/rate-limit-guard/` was absent in a live cloud session (2026-08-15), so there was no
fresh snapshot and no `stop-events.jsonl` either. Where the plugin reaches such a session and its
module runs, it writes inside that container, where only sessions in the same container can read
the file; no run of the module in a cloud session has been made, so this contract does not count on
it.

- **Pointer**: [mods overview: where mods run](https://code.claude.com/docs/en/plugins/mods#where-mods-run),
  the cloud session row.
- **As of**: 2026-10-03, Claude Code 2.1.288.
- **Recheck trigger**: that section changes whether mods run in cloud sessions, or a cloud run of
  this module is made.

That observation is **not a misconfiguration**. Under the capability-detection table above it
classifies as **unknown → reactive-only**. Consumers must not invent window percentages, pause
ends, or "healthy headroom" from the absence of the tee file. Fabricating proactive state is exactly
what fail-open forbids.

**What a cloud / remote consumer may use as signal (reactive only):**

1. **This session's own rate-limit errors**: API / harness text that names a rate limit or carries
   a reset time. Prefer the reset time in that text when present; otherwise backoff-and-retry.
2. **Sibling automation 429s visible to the session**: machine-readable infra comments or CI
   annotations on PRs/issues this session is already reading (for example review-lane comments that
   classify `api_error_status: 429` as `rate-limit`). Treat a live cluster of sibling 429s as thin
   headroom: shrink concurrency further; restore width only after those signals stop, never on a
   guessed recovery.
3. **`stop-events.jsonl` when present**: same read cadence as the reactive fallback below. In a
   typical cloud container the file is absent; absence is not evidence of healthy windows.

**Orchestration fallback when headroom is unobservable.** Sessions that size fan-out width from
rate-limit headroom (notably `session-flow`'s `/session-flow:orchestrate` imperative 7) treat
unobservable headroom as **thin by default**: start at a small conservative concurrent-worker cap,
prefer shorter waves over a wide tree, and scale only on the reactive signals above, never on the
missing tee file. The orchestrate skill owns the imperative wording; this contract owns the
classification that makes the fallback mandatory rather than optional.

**Documented residual (not closed here):** no producer is known to write the tee file where a cloud
/ remote consumer can read it today. Shipping or verifying one, whether fleet `cloud-environment` wiring, a synced
snapshot, or a harness/API exposure, is the residual path to proactive mode in cloud. Until it lands, unknown → reactive-only plus the
orchestration fallback above is the complete honest contract. Do not open a tracking issue solely
to restate this residual; the residual is this paragraph.

## Detection records (reactive fallback)

`~/.claude/rate-limit-guard/stop-events.jsonl` holds one JSON line per `StopFailure(rate_limit)` event,
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
payload carries no reset or quota data. A record means "a rate limit stopped a turn at this time",
nothing more. The file is bounded (rotated to the newest 100 records past 200).

Read cadence: a reactive-only consumer reads the file on entering reactive-only mode and again
before each new work claim. The recency baseline starts at the consumer's own start time, so records
older than that are history even on the first read, and each later resume attempt advances it.
Records with `detected_at` newer than the baseline are live signal; older ones are history and
never justify a new pause on their own. The baseline is per-consumer and in-memory; nothing
persists it, and a fresh consumer deliberately ignores prior sessions' records.

The contract directory holds the further shapes below, none of which readers consume, listed so
tooling sweeping the directory expects them. The module's helper creates a missing directory
owner-only (0700) and writes the contract file owner-only (0600).

- `stop-events.jsonl.lock`: the advisory-lock sibling the hook's serialized append and rotation use
  (present wherever `flock` exists).
- `.rate-limits.json.lock`: the helper's write lock, created exclusively for the length of one
  write and stolen when older than 60 seconds. Readers ignore it.
- `.rate-limits.json.tmp.w<pid>-<hex>`: the helper's atomic-write staging file. Normally it exists
  for well under a second between write and rename, and a failed rename removes it. One left by a
  killed writer is swept by the next write once it is older than 60 seconds. A cleanup tool should
  leave these alone: one may belong to a live concurrent write, and the helper reclaims them itself.

Left by versions before 0.12.0, which wrote the snapshot through a statusline tee, and safe to
delete after unwiring that tee (`/rate-limit-guard:setup` prints the steps): `.last-write`,
`spool/`, `.tee-disabled`, `.statusline-tee-path` (under
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/rate-limit-guard/`, which differs from the contract directory
under a relocated `CLAUDE_CONFIG_DIR`), and `bin/statusline-shim.sh`.
The helper also sweeps a `.rate-limits.json.tmp.<pid>.<random>` staging file those versions left
once it is older than 60 seconds.

## Invariants and boundaries

- **Single-account-per-machine is a narrowed gap, not a closed one.** The tee file is still
  last-writer-wins across every session on the machine: a login to a second account between writes feeds
  that account's healthy windows to lanes exhausted on the first. What changed is that a snapshot
  says **whose** windows it carries whenever the writer could attribute it, so a reader can detect
  the mismatch instead of being blind to it. The loop-lane convention §6 owns the framing. Of the
  three sides that design named (a writer-side field, reader-side invalidation of latched state, a
  lane-floor re-audit), the writer-side field has landed as `account.email` above; reader-side
  invalidation is a **MUST**, taken from the direct `.claude.json` read in the floor's "Account
  switch" bullet rather than from the tee file; and the lane-floor re-audit is the drift gate's job,
  which fails until every inlined copy carries the floor block (see "Consumers"). Two residuals
  keep this a gap rather than an invariant: the field is **absent** whenever the writer could not
  attribute the observation (the cases listed under "Tee file shape"), and absence is
  indistinguishable from "the writer never attributes on this platform"; and a reader that cannot
  read `.oauthAccount.emailAddress` keeps its latch, so a switch it cannot attribute goes unseen
  until the latched pause ends.
- **No shipped Monitor config.** Consumers arm their own session Monitor on the tee file (the
  staleness rule makes this mandatory while paused). The plugin ships no `experimental.monitors`
  entry, because Monitors is an experimental Claude Code component and this plugin takes no
  dependency on one until it stabilizes. Verified 2026-09-06 against Claude Code 2.1.263 and the plugins reference
  at `https://code.claude.com/docs/en/plugins-reference`, which calls monitors an experimental
  component and names `experimental.monitors` in `plugin.json` as the declaration key. Recheck when
  that page stops calling monitors experimental, or when a release note names the monitors component.
- **Fixed constants.** The tee path and the 95% threshold are contract constants, deliberately not
  configurable: cross-plugin consumers read the documented values, so a per-user override could
  silently split writer and readers. None of the plugin's 7 `userConfig` options changes either:
  `rate_limit_line_threshold` sets only when Claude gets the threshold line, and
  `rate_limit_guard_enabled` stops this machine's writes, never the path or the threshold readers
  apply.

## Consumers

The loop-lane convention's lanes (`work-items` `work-loop`, `work-items` `attend-queue`, and
`source-control` `babysit-loop`) inline the floor. Each records its guard mode (proactive /
reactive / unknown) in its lane telemetry every cycle, per the convention. Further surfaces inline
the same floor: the `docs-hygiene` `extract-ssot` orchestrated mode, the `source-control`
`pull-request` watch handoff, which checks the windows before starting a PR watcher, and the
loop-lane launch-prompt templates under `prompts/loops/` in the marketplace repository.

Every copy is drift-checked against the "Operable floor" block above by
`scripts/check-loop-lane-floor-drift.sh`, which runs in the marketplace repo's
`loop-lane-floor-drift-gate` CI lane and holds the registry of who inlines the floor; that
registry, not this list, is the authoritative roster. A change to the floor block here fails that
lane until every copy moves with it. The same check scans every tracked file for the floor's
opening bullet and fails on a carrier its registry does not name, so a new consumer cannot inline
this block and go unwatched.
