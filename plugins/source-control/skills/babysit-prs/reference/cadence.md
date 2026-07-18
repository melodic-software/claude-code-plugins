# Adaptive Cadence

Cadence states and thresholds for the queue loop. The snapshot engine emits
`recommended_cadence`; the loop derives its wake interval from it — `loop.md` owns the wake
mechanics, this file owns the states and thresholds behind the recommendation. Angle-bracket
slots (`<self-logins>`, `<watched-owners>`, `<state-dir>`) are filled from the
effective-configuration block in this skill's `SKILL.md`, which renders every key's resolved
value and its unset fallback; `<state-dir>` is the `state/babysit-prs` subdirectory of the plugin
data directory.

Cadence and fan-out answer two different questions and must not be conflated: cadence controls
how often the snapshot engine **detects** state (cheap, read-only, runs every cycle regardless);
`needs_worker` (`orchestration.md`) controls whether that cycle **spends a fresh worker** on a
given PR. A PR can sit in Active cadence (5-minute polling because CI is pending) for many
consecutive cycles while `needs_worker` stays `false` the whole time — the poll is cheap and
correct to repeat, a fresh 1:1 agent for "still pending, nothing new" is not. The moment that
PR's checks resolve, the same-cycle snapshot flips `needs_worker` to `true` and a worker is
dispatched immediately — cadence does not delay fan-out once there is something to act on.

## Cadence States

- **Active:** every 5 minutes when any watched PR has fresh failing CI, pending CI after a pushed
  fix, new blocking bot feedback, or a user-needed blocker.
- **Normal:** every 15 minutes when watched PRs are open and changing but not actively blocked.
- **Quiet:** hourly when watched PRs are green, approved or review-clean, and unchanged since the
  last snapshot.
- **Idle:** daily when there are no watched open PRs.

## State

Durable engine state lives under `<state-dir>`. Track:

- last seen PR head SHA
- last seen PR `updatedAt`
- seen material feedback IDs
- last classification
- last recommended cadence
- last failing/pending check identities (type, name, and workflow), alongside display names for
  reports (feeds `needs_worker`'s `checks_changed` delta so a CI resolution fires a worker even
  when it does not move `updatedAt`)
- last worker check-in time and exact head SHA per PR (feeds `needs_worker`'s `quiet_recheck_due`
  fallback — see `orchestration.md`; this is the one thing cadence alone cannot bound, since a PR
  can be correctly, repeatedly quiet-classified forever without ever being handed to a fresh
  worker)
- the two cross-cycle sweep counters — the last **complete** queue sweep's `generated_at` and the
  cycles-since-full-sweep count — persisted in the engine state file and stamped only on a
  complete queue sweep (see Cross-Cycle Counters Are Persisted below)

## Real-Elapsed-Time Detection

A loop cycle can fire much later than its nominal interval — the session was idle, a run was
missed, or a human re-triggered it by hand well after the last cycle. Compare the new snapshot's
`generated_at` against the previous cycle's own `generated_at` — never a separately-captured
wall-clock "now", and never the shared state file's `updated_at`: the feedback-ledger, refresh,
and review-trigger CLIs each stamp their own current time onto that shared field whenever they
run, independent of any snapshot, so it can read as recent even when the last full snapshot ran
much earlier. The prior `generated_at` comes from the orchestrator's own record of the last
cycle, backed by the persisted last-complete-sweep counter — never inferred from the shared
`updated_at`.

A gap larger than about an hour against a trustworthy prior `generated_at` is a cue that
real-world state has likely moved well beyond what the last cycle observed (new PRs opened, other
PRs merged outside this loop, heads moved from human activity) — treat it as a reason to run a
full snapshot and re-establish full coverage across the actionable queue, the same as a cold
start, rather than assuming only the PRs flagged `needs_worker` against stale state need
attention.

## Bounded Full-Sweep Interval

A cycle that already has a working set of known PRs can service real, visible work — worktree
pruning, targeted direct-gate rechecks on PRs already discovered — without ever running queue
discovery again. That targeted path is a legitimate per-cycle optimization, never a replacement
for periodic full discovery: it only ever re-examines PRs already in the working set, so a PR
opened by anyone else after the last full sweep is invisible to it. The failure mode is silent
and self-reinforcing precisely because the targeted path keeps finding real work — fixes land,
checks get rechecked, the loop *looks* healthy — while the queue it is actually servicing quietly
narrows to a shrinking, increasingly stale subset of the real one. Nothing about a targeted
recheck succeeding is evidence that discovery is still current.

Mandatory rule: regardless of how many consecutive cycles were serviced by targeted-only
rechecks, run a full queue discovery sweep (`--queue`) at least once every 4 cycles, or whenever
the real-elapsed-time gap against the last complete sweep's `generated_at` exceeds about an hour
— per Real-Elapsed-Time Detection above — whichever comes first. The two thresholds agree at the
default 15-minute Normal cadence (4 cycles is about 60 minutes), so this reuses that same
real-elapsed-time boundary rather than inventing a second one; at the 5-minute Active cadence,
the cycle count is the tighter of the two (4 cycles is about 20 minutes), which is correct — a
more volatile queue should be rediscovered more often, not less.

**Pre-sweep clock for a targeted-only cycle.** A targeted-only cycle never runs the snapshot
engine, so it has no fresh `generated_at` of its own to compare against the last complete
sweep's — without one, the real-elapsed-time branch of the mandatory rule cannot be evaluated at
all, and the ban on a separately-captured wall-clock "now" still applies to that
generated_at-to-generated_at comparison. This cycle's own queue-scope lease acquire/heartbeat
(mandatory every cycle regardless of targeted-only vs. full — see `orchestration.md`) is the one
narrow, tool-sourced exception: it returns its own freshly computed `updated_at`, a
single-purpose lease-mutex TTL timestamp written only by the lease helper — never by the
feedback-ledger, refresh, or review-trigger CLIs — so it is not the shared PR-state `updated_at`
this file already treats as untrustworthy for recency. When this cycle captured no fresher
snapshot timestamp of its own, use the queue lease's `updated_at` as the "now" side of the gap
against the last complete sweep's `generated_at`, solely to evaluate this one mandatory-rule
branch; it is never a substitute for the generated_at-to-generated_at comparison Real-Elapsed-
Time Detection requires everywhere else.

This mandatory rule applies only to queue-scoped cycles. A cycle invoked in single-PR mode
(`/source-control:babysit-prs owner/repo#42`, snapshotting with `--pr owner/repo#42`) is exempt:
`--queue` inspects every open PR under `<watched-owners>` while `--pr` is the one-PR selector, so
escalating a single-PR cycle to `--queue` at this interval would rediscover and let the loop
classify or act on unrelated PRs the user never asked it to babysit. A single-PR cycle's periodic
refresh keeps reusing its own existing scoped `--pr` invocation instead — the interval-counting
and cold-start rules still govern *when* that scoped refresh runs, they just never broaden it
into a `--queue` call.

The periodic sweep reuses the run's own scope exactly like every other snapshot call this cycle:
`--author @me` (your gh login, plus any `babysit_self_logins` extras) in default and worker mode,
dropped only in autopilot or on an explicit user instruction to widen (see `SKILL.md`). It is never an implicit license to broaden discovery
beyond the mode already in effect — a default or worker cycle's periodic sweep still never
surfaces another author's PR. The interval rule governs only *when* to rediscover, never *what to
do* with what the sweep finds: running a full sweep grants no action beyond what the run's actual
tier already permits — it is never itself grounds for a worker- or autopilot-only action
(resolving a thread, merging, dispatching a fix-round worker) the tier would not otherwise allow.

In acting cycles the periodic sweep also carries `--write-state`, exactly like every other
snapshot call this cycle — never an in-memory-only rediscovery that refreshes the orchestrator's
own working set without persisting it. A sweep that skips `--write-state` leaves the durable
snapshot stale for a newly discovered PR: the feedback-ledger and refresh helpers both reject a
PR or feedback id that is not present in the stored snapshot, so recording a disposition or
advisory round against a PR this sweep just found can fail until a state-writing sweep catches it
up.

## Cross-Cycle Counters Are Persisted

Two cross-cycle counters govern the mandatory rule: the last complete sweep's `generated_at` and
the cycles-since-full-sweep count. Both are persisted in the engine state file — not held only in
the orchestrator's memory — and stamped only on a **complete** queue sweep: queue mode exiting
zero with no `errors` in its output (`complete_queue = mode == "queue" and not errors`).
Increment the cycle counter on every cycle serviced by targeted-only work; reset it to zero only
on `complete_queue`. A queue call that errors or drops an owner/repo from discovery is
incomplete: leave both counters running so the next cycle retries the full sweep instead of
waiting out the rest of the interval on a gap it never actually closed.

Gate the persisted `generated_at` on the same `complete_queue` condition as the counter reset.
The snapshot engine stamps `generated_at` before it knows whether `errors` is empty, so an
incomplete sweep still returns a fresh `generated_at` alongside `complete: false` — that
timestamp must never overwrite the persisted last-complete-sweep value, which would silently
close the hour gap the mandatory rule relies on to force a retry. Update the persisted value only
when `complete_queue` is true; otherwise keep the last complete sweep's `generated_at` so both
thresholds keep signaling a retry until discovery actually succeeds.

Because the counters are persisted rather than in-memory-only, a fresh session no longer forces
an immediate full sweep by default: when the persisted counters are present, well-formed, and
pass the staleness check (the persisted last-complete-sweep `generated_at` is still within the
hour-gap threshold of Real-Elapsed-Time Detection), the session trusts them and continues the
interval already in progress. The cold-start rule — run a full discovery sweep immediately —
applies only when the persisted counters are absent, corrupt, or fail that staleness check.
