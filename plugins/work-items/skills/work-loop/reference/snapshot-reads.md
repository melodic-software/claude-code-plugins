# Cycle-start snapshot reads

`SKILL.md` step 1 takes the cycle-start snapshot this file governs; both stop modes test their exit
condition against it, and `first_drain_complete` (which lifts the first-drain C3 ratification gate)
is set from it. An empty id set passes the drain exit test vacuously, so the snapshot is trusted only
when the reads behind it were complete.

## The reads

- **Frontier**: the seam's `list-frontier --autonomous`. Its envelope carries `truncated` (the
  tracker seam's `CONTRACT.md`, "JSON output contract").
- **Open items**: the seam's `list-items --state open`, which every bundled adapter serves. Its
  envelope carries `truncated` the same way; each adapter decides it exactly, by reading one item
  past `limits.list_items_max` where the provider allows, so a backlog of exactly the ceiling is
  complete. Never pass a provider-specific flag such as `--limit` here.

An envelope with no `truncated` field falls under "Completeness unknown" below, whichever read
returned it.

## A read that is not complete aborts the cycle

When any read exits non-zero (seam exit 8 included), prints no parseable result, or reports
truncation, the cycle aborts with **no state change**:

- no intake sweep, admission, execution, escalation (except the truncation escalation below), or
  exit evaluation;
- every durable counter, `first_drain_complete` included, is written back as it was read. Only
  `heartbeat_at` moves, so the lane is not mistaken for a dead one;
- the cycle report leads with `snapshot unusable: <read>: <reason>`, and the next cycle is scheduled
  as usual.

## A truncated read escalates at once

Truncation does not clear on its own: a backlog past the ceiling reads as truncated every cycle,
and because the abort writes `no_progress_streak` back unchanged, the threshold would never be
reached. So in the same aborted cycle, without waiting for the streak:

- raise the stall escalation (`SKILL.md`, "No-progress detector", "Stall escalation"), with the
  same title, label, marker and at-most-one-open check, reporting the truncated read, the bound
  adapter, and its `limits.list_items_max` instead of a streak;
- a **headless** launch (as defined in [invocation-argv.md](invocation-argv.md), "Headless
  launches") then stops the loop with: `work-loop: snapshot truncated: <read> returned more than
  the <adapter> adapter's list_items_max of <n> items; the lane cannot see its whole backlog`. An
  interactive launch schedules the next cycle as usual.

The escalation is a tracker write, not a durable-state change: every counter is still written back
as read. A read that errored or was unparsable gets no escalation; those are transient.

A failed read is never reported as an idle cycle. An empty snapshot from complete reads is an empty
backlog; an empty one from a failed or skipped read is not.

## Completeness unknown

A frontier or open-items envelope with no `truncated` field comes from a consumer adapter written
before the contract added it. Its completeness is **unknown**, not complete: the cycle runs, but its snapshot
never satisfies the drain exit test or sets `first_drain_complete`, and the report says
`snapshot completeness unknown`. The drain-terminal stop still applies, because stopping lifts no
gate. Regenerating the adapter with `/work-items:onboard-adapter` restores the flag.
