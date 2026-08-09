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

**Resolved dimension overrides gate this dispatch, ahead of everything else in this file.** The
widening pair is necessary, never sufficient. Resolving review threads is an exercise of autonomy
**dimension 3 (thread resolution)**, so the lane's resolved value for that dimension binds the
dispatch itself and not merely the mechanic invoked after it (`SKILL.md` Cycle shape, step 4,
"Dimension overrides bind by tier flooring"). An invocation whose own argument line narrows thread
resolution below the authority this dispatch needs — `autopilot --merge c3-this-run
--thread-resolution safe` is the live shape — gets **no dispatch at all**: the PR escalates and the
cycle report names it override-constrained. `${CLAUDE_PLUGIN_ROOT}/reference/config-resolution.md`
makes invocation arguments win for every dimension but merge, and an argument narrowing thread
resolution cannot be answered by dispatching a fresh subagent that resolves threads anyway.

**Resolving a thread requires a D7.5 verification ledger, per finding, before the wrapper is
called.** The guarded wrapper checks authorship and comment-state pins; it cannot check whether a
finding was actually addressed, and `review-discipline.md`'s D7.5 routes a current bot thread here
precisely *because* this dispatch is supposed to establish that. Without the ledger the dispatched
agent could resolve a current thread on an unaddressed finding and clear the merge gate's
zero-unresolved-threads predicate — the same self-satisfaction the worker-side outdated-only guard
exists to prevent, moved one hop. So: extract every finding in the thread (one comment carrying N
findings is N work items), and record for each one the disposition plus its evidence —

<!-- contract-restatement-begin: D7.5-thread-eligibility -->

- `VALID (fix now)`: the pushed commit SHA that fixes it, verified present on the live PR head, and
  the D7 follow-up citing it.
- `VALID (defer)`: grounded per D4.6 — the provenance test passed (the defect reproduces on the <!-- contract-restatement-begin: D4.6-deferral-grounding -->
  base branch), and the tracker item exists, carries the finding's own evidence, and its cited id
  re-queries successfully. <!-- contract-restatement-end: D4.6-deferral-grounding -->
- `INCORRECT`: the counter-evidence, read from the code or docs at the live head rather than
  asserted.
- `UNCERTAIN`: not resolvable. It escalates, and so does the thread.

**Every** finding in the thread must hold an eligible disposition; one addressed finding never
makes the thread eligible while a sibling finding is open, because a resolved thread drops all of
its comments from the readiness count. Any finding the dispatched agent cannot verify to this
standard means **no resolution**: leave the thread unresolved, do not merge, and escalate with the
unverifiable finding named. The ledger is reported back with the dispatch result, so what was
verified is inspectable rather than asserted.

<!-- contract-restatement-end: D7.5-thread-eligibility -->

**A blocker needing a code change runs the full per-PR worker lifecycle** — isolated PR worktree,
HEAD asserted at the live PR head, commit and refspec push (`babysit-prs/reference/safety.md`) — not
the wrappers alone, which implement merge and thread resolution and create no worktree; a lane
launched from a neutral directory has no usable tree without it. That sentence governs how a **code
change** is made and names no resolve mode; the mode is the next section's and wins wherever the two
could be read against each other.

## The resolver mode, and the two thread shapes it refuses

**The mode is `--independent-resolver`, never `--autonomous`.** The two are parallel modes and the
independent one is not a relaxation of the other
(`babysit-prs/scripts/babysit_resolve_thread.py`). `--autonomous` is the *merging worker's* own
guard: it refuses any thread not already `isOutdated` before that worker's own push, which is
exactly the **current, non-outdated** bot thread `review-discipline.md`'s D7.5 routes here. Running
it from this dispatch could therefore never clear the one blocker class the dispatch exists to
clear. `--independent-resolver` drops the `isOutdated` requirement and replaces it with the two
properties this dispatch already supplies — independence (a fresh context that is neither the
merging worker nor the author of the fix) and machine-validated disposition evidence. Independence
is a property of the dispatch and unverifiable by the script, which is why the evidence half is
machine-checked.

**The D7.5 ledger is the mode's input**, one flag tuple per disposition, each validated against the
world rather than trusted:

- `VALID (fix now)` → `--disposition fixed --fix-commit <sha>`, the sha reachable from the PR head.
- `VALID (defer)` → `--disposition deferred --tracker-item <id>`, the item existing and open.
- `INCORRECT` → `--disposition incorrect --counter-evidence <text>`, the text already present in a
  reply on the thread posted by someone **other than the thread's opener** — so the reply goes up
  first and a finding's own author cannot supply the words that rebut it.
- `UNCERTAIN` → no resolve call at all: escalate, per the ledger rule above.

Missing, unparsable, or unverifiable evidence **refuses** the resolve rather than warning, and only
a confirmed 404 reports the evidence-specific refusal, so an outage is never read as a caller lying
about its evidence. A refusal is the recoverable direction: the thread stays unresolved and the PR
escalates.

**Two thread shapes the mode refuses outright, which therefore escalate rather than resolve.** Named
here because the ledger's per-finding phrasing does not by itself imply either:

- **More than one source finding in the thread** — refused as `skipped-multi-finding-thread`. One
  `--disposition` is a claim about one finding while resolution clears the whole thread, so
  resolving on a single evidence tuple would drop the thread's other findings out of the readiness
  denominator. An unknown count — a truncated comment page could hide another finding — refuses the
  same way. The per-finding ledger rule above still governs the dispatched agent's judgment; this is
  the wrapper declining to act on such a thread at all, so the PR escalates with the ledger
  reported.
- **A severity-flagged thread** — security or P1 — refused here as in `--autonomous`. The severity
  bright line does not move for an unattended path, and this dispatch is one.

Everything `--autonomous` guards other than `isOutdated` still binds: bot-authored threads only, a
single pinned `--thread-id` carrying both TOCTOU pins, bulk resolves and `--allow-unpinned-thread`
refused, and `--include-human` refused.

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
  set. What the paired-argument invocation unlocks is this dispatch path alone
  (`babysit-prs/reference/safety.md`, "Security/P1 escalation has no exception"); it widens neither
  the severity bright line nor human blocks.
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
