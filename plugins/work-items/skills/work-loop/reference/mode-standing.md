# Standing mode (default)

The lane keeps watching the backlog indefinitely. Idle cycles back the wakeup delay off toward the
longest delay `ScheduleWakeup` allows. The `/loop` expiry bounds a standing lane per the
loop-lane convention: `loop_started_at` in durable state makes the approaching expiry visible, and
an expiry hit is handled exactly like a budget hit (restart-request + clean stop).

- **Pointer**: when sizing the idle backoff or the stale-heartbeat threshold, fetch
  [scheduled tasks § Let Claude choose the interval](https://code.claude.com/docs/en/scheduled-tasks#let-claude-choose-the-interval)
  live; when timing the expiry, fetch
  [§ Seven-day expiry](https://code.claude.com/docs/en/scheduled-tasks#seven-day-expiry) live.
- **As of**: 2026-10-11
- **Recheck trigger**: either section changes the longest wakeup delay or the expiry window, or a
  release note names `/loop` or `ScheduleWakeup`.

## Exit condition

A standing invocation **does not** stop when the drain snapshot is satisfied or when the
drain-terminal state is reached. On the first cycle where the drain snapshot would be satisfied,
on a snapshot `SKILL.md` step 1 counts as complete and never on an errored, truncated, or
unknown-completeness one, propose first-drain completion per
[first-drain-ratification.md](first-drain-ratification.md) (a person ends the earn-trust period), report the outcome,
and **continue** with `ScheduleWakeup`. New intake arriving on a later cycle is swept on that
cycle, not left for a relaunch.

Standing exits are limited to:

- explicit user request (hard stop),
- a cycle-budget or `/loop` expiry hit (restart-request + clean stop, per the convention),
- instance-collision detection (escalate + clean stop),
- or an unrecoverable configuration error (missing binding, rejected argument).

When the snapshot shows only human-gated or escalated items with no PR in flight
(drain-terminal shape), report that shape in the cycle report and keep looping. The attended queue
owns those items; this lane idles with backoff rather than terminating.

## Post-snapshot intake report

On cycles that do not exit, the cycle report still names intake that arrived after the snapshot and
was left unworked when actionable work existed, per the convention's "reported, never chased"
rule. In standing mode there is always a next cycle, so that report is informational rather than a
final handoff.
