---
type: handoff
handoff_shape: 4
checks: 3
date: 2026-10-09T17:30:00Z
topic: lease-table
session_id: 3b6f0c2a-8d41-4e7a-9c15-5a2e7d9f0b31
transcript: unresolved (session 3b6f0c2a-8d41-4e7a-9c15-5a2e7d9f0b31, projects-root /work/projects)
chain_root: 20261009T173000Z-handoff-lease-table.md
hop: 1
archive: archive/20261009T173000Z-handoff-lease-table/
archive_from: 1
next_rule_id: 1
next_question_id: 1
next_decision_id: 1
repo: https://github.com/example/scheduler.git
---

## Original goal

**Goal (verbatim):**
> "Replace the cron lock with a lease table so two schedulers never run the same job."

**Intent (verbatim):** None stated.

**Vision (verbatim):** None stated.

**Amended:** None.

Opening ask:
Replace the cron lock with a lease table so two schedulers never run the same job.

## Resumption brief

On `feat/lease-table`: migration 0007_leases.sql and scripts/backfill.sh are committed; the renewal loop in src/lease.ts is not started. Next: write it (Remaining actions, item 1). Read Current rules first.

## Remaining actions, in order

1. Write the renewal loop in src/lease.ts.

## Completion criteria

- [ ] two schedulers never run the same job (settle: run the soak test in scripts/backfill.sh's README)

## Open questions

None. Nothing is unknown.

## Current rules

- [R1] Two schedulers never run the same job.

## Standing preferences

None. No standing preference this chain.

## Decisions in force

- [D1] Lease TTL is 90 seconds, renewed every 30 seconds, chosen over 300 seconds because failover must finish inside two minutes.
- [D2] Keep the cron lock as a fallback until the renewal loop ships.

## Pending commands

None. No command waits on the user.

## Environment to re-establish

- Branch `feat/lease-table`.
- A background shell was running `bash scripts/backfill.sh`, logging to .work/backfill.log; its last line was "batch 41/120" when this session ended.

## This session

did: committed the leases migration and started the backfill · left: the renewal loop and the backfill run
Re-scan: the re-scan read the lossless on-disk transcript

## Review before you continue

- None. This file suffices for the next action.

## Direction changes

- [h1] start: a leases table beside the cron lock (owner-directed, "replace the cron lock").

## Observations

- Moved: archive/20261009T173000Z-handoff-lease-table/h1-3b6f0c2a.md#Observations (h1)

## Suggested skills

None. Remaining work runs inline.

## Prior sessions

None (first hop).

## Resume prompt

`/clear`, then copy everything between the dashed lines:

──────────────────────────────────────────────────────────
Read @/work/repo/.work/handoffs/20261009T173000Z-handoff-lease-table.md, confirm its Original goal still governs the remaining next steps, then continue them. For the next save-point invoke /session-flow:handoff via the Skill tool; never write a handoff file free-hand.
Prior session: 3b6f0c2a-8d41-4e7a-9c15-5a2e7d9f0b31.
Handoff origin: https://github.com/example/scheduler.git .work/handoffs/20261009T173000Z-handoff-lease-table.md
Next:
Write the renewal loop in src/lease.ts
──────────────────────────────────────────────────────────

Or reopen the producing session in place: `claude --resume 3b6f0c2a-8d41-4e7a-9c15-5a2e7d9f0b31`.
