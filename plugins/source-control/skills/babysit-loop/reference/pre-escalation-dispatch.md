# Pre-escalation resolution dispatch (explicit-`autopilot` only)

The full contract for the one resolution attempt the explicit-`autopilot` widening adds ahead of an
escalation. This path is reachable **only** when an invocation's own argument line typed both the
literal `autopilot` tier argument and `--merge c3-this-run`; every other invocation escalates
directly and never reads this file. `SKILL.md`'s "Escalation" section owns when the dispatch fires
and the bounds it cannot cross; this file owns how it runs.

## The dispatch

Before a merge-eligible (C1-C3) PR is escalated for a **machine-escalated** `needs-human` item, an
open machine-authored finding, or a contradictory/unresolved **bot** review thread, and only when
this invocation's own argument line typed both the literal `autopilot` tier argument and
`--merge c3-this-run` (the widening pair): dispatch a fresh subagent at the **frontier tier** — §3's
top tier row, requested by tier and resolved to a live-updating model alias through that section's
"Runtime resolution is by model alias only", never a dated model ID and never a family name written
into this lane as the tier's *definition* (tiers are ordered by capability; a family mapping rots).
A run that cannot establish which alias currently satisfies `frontier` **escalates rather than
dispatching** — inheriting the session's model, or a lower review-work model, forfeits the
capability this dispatch stands on. The subagent shares no context with whatever produced the PR or
previously replied on the blocking thread, and **runs under the PR's worker lease**: acquire and
heartbeat before it starts, release after, exactly as `babysit-prs` requires before any per-PR fix
or worker assignment (`babysit-prs/reference/safety.md` and
`babysit-prs/reference/orchestration.md`); the guarded wrappers pin comment state, not concurrency
ownership, and a lease another worker already holds means no dispatch at all. Brief it with the
blocker, the PR, and the convention's independence and frontier-tier requirements; it replies and
resolves threads through babysit-prs's guarded-mutation path, never a raw mutation.

**A blocker needing a code change runs the full per-PR worker lifecycle** — isolated PR worktree,
HEAD asserted at the live PR head, commit and refspec push (`babysit-prs/reference/safety.md`) — not
the wrappers alone, which implement merge and thread resolution and create no worktree; a lane
launched from a neutral directory has no usable tree without it.

## Four blocker classes this dispatch never touches

Each because the invoked mechanic's own contract already owns them and this exception does not amend
those contracts:

- **Operator-parked items.** The `needs-human` role label marks machine-*escalated* and
  operator-*parked* items alike; only the machine escalation marker distinguishes them (loop-lane
  convention, "Escalation contract"). An item wearing the label without that marker belongs to the
  attended queue, not this lane: no dispatch, and step 3 withholds the PR from the merge-capable
  set — dispatching on the label alone would answer an operator-owned question with an agent.
- **Human blocking feedback.** A human `CHANGES_REQUESTED` review, explicit human blocking
  language, or an unresolved inline human thread stays a stop-and-ask condition until GitHub state
  resolves it — escalate, never fix or resolve past it (`babysit-prs/reference/feedback.md`,
  "Human Feedback"). No dispatch is made, and step 3 withholds the PR from the merge-capable
  set. The one exception `babysit-prs` gained in this change is
  scoped to security/P1 escalation and to that dispatch path alone (`babysit-prs/reference/safety.md`,
  "Security/P1 escalation"); it does not widen to human blocks.
- **Merge conflicts.** These route to the dedicated fresh conflict-resolution worker
  (`babysit-prs/reference/orchestration.md`, Merge Conflict Resolution), which integrates
  **merge-only and never rebases** — rebasing a PR branch needs the force-push babysit-prs forbids
  cross-tier. This dispatch never resolves a conflict itself and never rebases.
- **C4/C5 PRs.** Already excluded at the rung partition (`SKILL.md` Cycle shape, step 3) — including
  the provenance-derived C5 override and the diff-derived C4 veto — and they escalate normally.

## After the dispatch

If the dispatch resolves the blocker, **re-snapshot the PR and rerun step 3's provenance, C4-diff and
rung partition before** its normal `autopilot`-tier invocation and gate — the first partition read
the cycle-start diff, and a resolution that pushed code can have turned a C2/C3 change into a
refactor, migration, or contract change that the downstream merge gate does not class-check. A PR
that leaves the eligible set on that second partition escalates instead of merging. The normal
worker's own final push obeys the same head-pinning rule (`SKILL.md` Cycle shape, step 3, "The
verdict authorizes a head SHA, not the PR"). If the dispatch cannot resolve the blocker — including
any case where the subagent itself is uncertain the resolution is correct — the PR escalates exactly
as it would without this exception; this dispatch adds one resolution attempt, it never removes
the escalation path or lowers the gate's bar.
