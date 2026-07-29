# The restart-request consumer (#1653)

Why a stopped lane needs an out-of-harness reader, how the consumer binds to lane
telemetry, and the operator steps that put it on a schedule. The executable
contract — actions, options, exit codes, the relaunch predicate — lives in the
`--help` header of [`scripts/restart-consumer.sh`](../scripts/restart-consumer.sh);
this file is the operator- and reviewer-facing rationale, not a copy of it.

## The gap

A loop lane that hits its per-session cycle budget or the `/loop` seven-day expiry
writes a restart ask into the `restart_request` field of its telemetry state block
and stops cleanly — a running loop cannot relaunch itself, and `SKILL.md` documents
that a relaunch is the only fresh-context reset a lane gets. Until now nothing read
that field, so every budget or expiry hit was a terminal manual-restart state. The
consumer is the missing reader: on each scheduled run it checks every configured
lane's telemetry and relaunches, through `lane-launcher.sh restart`, the stopped
lanes that asked.

## Why the schedule is OS-owned

The discriminating question is *what survives the failure it remediates*:

| Mechanism | Clean budget/expiry stop | Lane crash | Harness restart / reboot |
|---|---|---|---|
| Watchdog/wake lane (`/loop` + `ScheduleWakeup`) | yes | no | no |
| Stop hook on the dying lane | conditionally | no | no |
| OS scheduler (chosen) | yes | yes | yes |

- A **watchdog lane is circular**: it is itself a `/loop` session bounded by the
  same seven-day expiry, cycle budget, and crash risk it exists to remediate.
  Nothing restarts the restarter.
- A **Stop hook** is non-circular and event-driven, but it structurally cannot
  fire when the failed thing is the process or the machine — and those are two of
  the three failure modes the gap is about. **Deferred, not discarded**: revisit
  if Stop-hook input gains a session discriminator or lane bodies mandate
  `ScheduleWakeup(stop: true)`, and then only as a latency layer on top of the OS
  schedule, never a replacement.
- Cloud `/schedule` routines stay rejected for lane work — they cannot reach a
  local checkout (`prompts/loops/loop-lane-prompts.md:703-708`). Not re-litigated.

Decision record with the full bake-off: issue #1653.

**The polling tick is not lane pacing.** Lanes remain self-paced via
`ScheduleWakeup`; the consumer never sets, nudges, or replaces a lane's cadence.
On a tick where no configured lane has a non-null `restart_request`, the run is a
no-op that only refreshes the consumer's own freshness telemetry.

## The shape consumed

Discovered from the producers (`work-items:work-loop`,
`source-control:babysit-loop`), not assumed: each lane upserts one
sentinel-marked comment (`<!-- claude-ops:lane-telemetry marker=... -->`) on its
`Lane telemetry: <lane>` issue whose fenced JSON state block carries
`restart_request`, emitted as `null` in every published example. No producer
specifies a non-null shape, so the consumer treats **any non-null value** as a
request and reads an optional `{"requested_at","reason","cycle"}` object form for
reporting only. No producer change is in scope.

The comment is a **signal, never a target**: lane identity, prompt, model,
effort, and settings all come from the operator's local lane config, and nothing
read from a comment is interpolated into a command or path. A telemetry comment
can never name a lane the operator has not configured.

## Operator setup — registering the schedule

Registration is an **operator action**; neither the script nor the skill ever
registers, edits, or deletes a scheduled task. Run `print-schedule` for commands
generated from your machine's real paths:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/lanes/scripts/restart-consumer.sh" print-schedule
```

It emits, for Windows first (matching the `ClaudeCodeOtelPrune` precedent in the
observability skill, which owns the same `schtasks` posture):

- a `schtasks /Create ... /SC MINUTE /MO <interval>` poll task and a
  `/SC ONLOGON` companion for cold start after reboot — both `/RU "%USERNAME%"
  /IT /RL LIMITED`: run as the logged-on user, no elevation, no stored
  password. The `/TR` payload carries `consume-restarts run` — `run` is
  load-bearing, because the script's default action is the read-only `check`
  and a schedule registered without it would report forever and relaunch
  nothing;
- the matching `schtasks /Delete` reversals;
- the cron/launchd/systemd-user equivalent for macOS/Linux.

Run every `schtasks` line from **cmd.exe**, each on one line as printed — not
Git Bash, whose MSYS path conversion rewrites `/`-style options (`schtasks
/Query` becomes an invalid `C:/Program Files/Git/Query` argument). The emitted
`/TR` paths are Windows-form (`cygpath -w`), since cmd.exe cannot use the
MSYS-form paths Git Bash resolves.

**Verify:** from cmd.exe, `schtasks /Query /TN "ClaudeOps Lane Restart
Consumer"`, then `schtasks /Run /TN "ClaudeOps Lane Restart Consumer"` and
confirm a fresh `last-cycle:` on the consumer's **telemetry comment**. That one
signal, and not a local-file alternative, is the whole check: `last-cycle:` is
written only by `upsert_own_telemetry`, which returns early unless the action is
`run` — so a fresh timestamp proves the registered task carries the load-bearing
`run` token, which is exactly the defect a registration can silently have.

The local run ledger is deliberately **not** an accepted alternative here: it
answers "did something run", where this step must answer "did a **`run`** run".
`append_ledger` is likewise gated on the action being `run`, resolving that in
favour of the `--help` contract's read-only `check` rather than the other way
round — a `check` an operator runs by hand must never move the circuit breaker's
memory, and a ledger that a `check` could write would satisfy the very check
above on the failure it exists to catch.
**Reversal:** the `schtasks /Delete /TN ... /F` lines `print-schedule` prints,
from cmd.exe.

Two scheduled forms, different trade-offs:

- **Headless skill form** — `claude -p "/claude-ops:lanes consume-restarts run"`.
  Survives plugin updates (the skill resolves `${CLAUDE_PLUGIN_ROOT}` freshly at
  each invocation, so the task never embeds a plugin cache path that rots), but
  each tick is a paid model turn. Bound the spend: `claude` supports `--model`
  and `--max-budget-usd` (verified on this machine, claude 2.1.220) — pin a
  cheap model and a hard cap on the scheduled command.
- **Offline script form** — `bash <abs-path>/restart-consumer.sh run`. Zero
  model cost (the reader is deterministic), but the embedded absolute path
  points into the plugin cache, which **changes on plugin updates** — the same
  caveat the `ClaudeCodeOtelPrune` precedent documents. Re-run `print-schedule`
  and re-register after updating the plugin, or keep an operator-owned shim that
  resolves the current plugin root at run time. If the path stops resolving the
  task fails loud in Task Scheduler history; the consumer's telemetry comment
  goes stale in the morning brief, which is the designed detection.

Windows-first posture, inherited from the precedent: the Windows commands are
concrete and tested for shape; the macOS/Linux lines are equivalents, not a
parity claim.

### Unverified (labeled, not assumed)

- **Fully-logged-off operation.** `/IT` runs the task only while the user is
  logged on (a locked session qualifies). Running logged-off needs the S4U form
  (`/RU <user> /NP`), which is **UNVERIFIED** here — nothing was registered on
  the authoring machine. Until verified, treat coverage as "logged on or
  locked", not "always".
- **Whether a `claude --bg` lane launched from a scheduler-spawned process
  outlives that process on Windows** (job-object process-tree kill is the
  hazard). **UNVERIFIED.** The consumer degrades safely rather than assuming:
  after each relaunch it re-polls `claude agents --json` and records a `failed`
  row (exit 5, flagged in its telemetry) when the lane never appears — so if
  the assumption is false the symptom is loud, attributable, and rate-limited
  by the circuit breaker instead of a silent restart storm.

## Observability (the consumer must not become the next silent gap)

- **Morning-brief surfacing.** On every `run` the consumer upserts its own
  sentinel-marked comment (marker `claude-ops:restart-consumer`) carrying the
  same `lane:` / `last-cycle:` / `flags:` header `morning-brief.sh` already
  parses. The comment must land on the ONE issue that reader resolves, so the
  consumer's default discovery reuses the brief's own title search; when that
  finds nothing it falls back to an issue titled exactly
  `Lane telemetry: restart-consumer`, which the brief reads only when both
  tools are pinned to it (each has a `--telemetry-issue`). When the comment
  lands on the brief's issue, the consumer appears in
  `/claude-ops:morning-brief` with no reader change and inherits its
  `STALE (>Nh)` detection — a consumer whose schedule stops firing surfaces as
  a stale lane, which is exactly the failure a run log alone would miss. With
  no resolvable issue at all, the run degrades loudly to ledger-only with a
  warning naming the fix.
- **Run ledger.** A `run` appends a JSONL row under
  `<data-dir>/lanes/<repo-key>/restart-consumer.jsonl` for each lane whose
  decision is an **incident** (`restarted`, `failed`, `error`, `api-error`) —
  the detail layer, and the circuit breaker's memory (default: max 3 restarts
  per lane per rolling 24 h; a tripped breaker exits 5 and flags the telemetry).
  The routine per-tick decisions are reported and land in the telemetry comment
  but are not ledgered: on a 15-minute schedule they would add hundreds of rows
  a day, forever, to a file the breaker re-reads once per lane per tick, and
  none of them can change a breaker verdict. The file therefore grows with
  incidents rather than with the polling interval, and stays append-only — a
  rewrite-the-file pruner would put the breaker's own memory at the mercy of a
  bug in the pruner.
- **The breaker fails closed.** A ledger that does not parse reports the budget
  as **spent**, with a warning naming the file. The opposite (treating an
  unreadable ledger as zero restarts) would silently restore the full budget on
  exactly the file a crashed writer left behind, turning corruption into an
  unbounded restart loop.
- **One mutating run at a time.** A `run` holds an mkdir-atomic sentinel
  (`<data-dir>/lanes/<repo-key>/.restart-consumer-lock`, the idiom the
  observability prune's `.prune-in-progress` established) across the whole
  read → decide → relaunch → append span. This is not theoretical: the
  registration above is **two** scheduled tasks, and at logon the poll and the
  `ONLOGON` companion both fire — Task Scheduler's instance policy is per task,
  so it cannot serialize them. Unsynchronized, both read the same breaker count,
  both relaunch, and one lane name ends up with two `claude --bg` sessions and
  two `restarted` rows for one effective restart. A run that cannot take the
  lock skips cleanly: exit 0, a `lock-held` flag, nothing launched and nothing
  written. A lock left by a hard-killed run (no EXIT trap) ages out after an
  hour so an unattended schedule cannot wedge permanently. `check` and
  `--dry-run` mutate nothing and never contend.
- **Exit codes are honest.** A relaunch that fails, never comes up, trips the
  breaker, or a lane whose telemetry could not be READ (`api-error` — never
  conflated with `no-state`, which means "the lane did not ask") exits 5; Task
  Scheduler history shows the non-zero result. A tick skipped for the lock is
  exit 0: it is a correctly-serialized no-op, not a failure.

## Telemetry binding per lane

Optional `lanes[].telemetry` config keys (`issue`, `marker`, `repo`) bind a lane
to its telemetry comment; every one has a working default (issue resolved by the
exact `Lane telemetry: <lane>` title, marker matched by the shared sentinel plus
a `restart_request`-bearing state block, repo defaulting to the consumer's
`--target-repo`). Full semantics: the script's `--help` header.
