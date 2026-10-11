# Cycle-start snapshot reads

`SKILL.md` step 1 takes the cycle-start snapshot this file governs; both stop modes test their exit
condition against it, and `first_drain_complete` (which lifts the first-drain C3 ratification gate)
is set from it. An empty id set passes the drain exit test vacuously, so the snapshot is trusted only
when the reads behind it were complete.

## The reads

- **Frontier**: the seam's `list-frontier --autonomous`. Its envelope carries `truncated` (the
  tracker seam's `CONTRACT.md`, "JSON output contract").
- **Open items**: the adapter "List items" projection with an explicit `--limit` set to one more than
  the adapter's `limits.list_items_max` (from the seam's `capabilities`). That projection carries no
  flag, so a read returning more than `list_items_max` rows counts as truncated; a backlog of
  exactly `list_items_max` items is complete.

## A read that is not complete aborts the cycle

When any read exits non-zero (seam exit 8 included), prints no parseable result, or reports
truncation, the cycle aborts with **no state change**:

- no intake sweep, admission, execution, escalation, or exit evaluation;
- every durable counter, `first_drain_complete` included, is written back as it was read. Only
  `heartbeat_at` moves, so the lane is not mistaken for a dead one;
- the cycle report leads with `snapshot unusable: <read>: <reason>`, and the next cycle is scheduled
  as usual.

A failed read is never reported as an idle cycle. An empty snapshot from complete reads is an empty
backlog; an empty one from a failed or skipped read is not.

## Completeness unknown

A frontier envelope with no `truncated` field comes from a consumer adapter written before the
contract added it. Its completeness is **unknown**, not complete: the cycle runs, but its snapshot
never satisfies the drain exit test or sets `first_drain_complete`, and the report says
`snapshot completeness unknown`. The drain-terminal stop still applies, because stopping lifts no
gate. Regenerating the adapter with `/work-items:onboard-adapter` restores the flag.
