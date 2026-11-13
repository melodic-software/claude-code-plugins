# Drain mode (`--drain`)

The lane stops when the cycle-start snapshot shows every retained id closed or covered by an open,
non-draft close-linked PR, or when the drain-terminal state applies. Lane-infrastructure items never
gate the drain (telemetry issues, open spec containers, open wayfind maps and their decision items). The exclusion contract is owned by
`SKILL.md` "Exit condition" and cited from the loop-lane convention; this file does not restate it.

## Exit condition

Evaluate at cycle end against the cycle-start snapshot's **retained ids, never a fresh seam read**:
every id the snapshot captured, its open items and its autonomous-frontier candidates alike, is
closed or has an **open, non-draft** PR the bound adapter's "Open linked PRs" operation reports as
close-linked (the provider's own computed close-linkage, whose query mechanics and draft exclusion
the adapter owns).

There is deliberately **no second frontier-emptiness limb**. Re-running `list-frontier --autonomous`
here would see items that joined the frontier *after* the snapshot, precisely the mid-cycle intake
step 1 reports and never chases, so a bot filing agent-ready items could hold the drain open
forever. Absence from a later frontier read is also not resolution: an item another session claims,
or one that becomes blocked, leaves the frontier unresolved. Nothing is lost by dropping the limb:
the frontier is derived by filtering `state == open`, so a snapshot frontier candidate is a
snapshot open item either way, and the single test above already covers it, including an item the
snapshot held as untriaged intake that step 2 promoted mid-cycle. That item still holds the drain
open, and it is worked once the admission gate passes it and a cap slot is free.

The test runs only on a snapshot `SKILL.md` step 1 counts as complete. A cycle whose snapshot read
errored, was truncated, or came back empty because a read failed has already aborted before this
point, and a snapshot of unknown completeness never satisfies it: an empty id set passes the test
vacuously, so it may be trusted only when the reads behind it were complete.

Satisfied → the drain is complete: write the final report (items
escalated to a human first, then items closed and PR'd), apply the post-snapshot intake report below, and stop cleanly.

When the drain stays open because a retained id is covered only by a draft closing PR or by the
in-flight exclusion, the cycle report names those ids with the same PR number, draft state, and age
as `SKILL.md`'s in-flight line, from the adapter's reporting reduction. An id whose PR is past the
`work_loop_in_flight_stale_days` bound was escalated to a human (`SKILL.md` "In-flight
precondition"); the final report lists each such id among the items escalated to a human, with its
PR number, draft state, and age, and it counts as human-gated for the drain-terminal test below
even though its PR is still open, draft or ready. Its PR is not "in flight" for that test.

## Drain-terminal state

When every remaining open item in the snapshot is human-gated or escalated and no PR is in flight
(a stale PR whose item was escalated does not count), report and stop cleanly rather than idling forever, leading the report with those human-gated and
escalated items. Apply the post-snapshot intake report below
before stopping.

Human-gated here means held for a person per the tracker seam's "Reading an item's status"
([`tracker-seam.md`](../../../reference/tracker-seam.md)): the human-gated role label, a hold-state
label, or a status in `WIT_HUMAN_FLOOR_STATUS_STATES`, read from the snapshot's status read
([snapshot-reads.md](snapshot-reads.md)), whose values count only trusted setters when the binding
configures that.

## Cordoned items

An open retained item whose row carries a `milestone` listed in `cordoned-milestones` counts toward
neither the exit condition nor the drain-terminal test. Those names live only in
`.github/actions/resolve-config/admission-rules.json` on the target's default branch
([snapshot-reads.md](snapshot-reads.md), "The reads"); no such file means no cordoned milestones.
A row whose `milestone` is `null` or absent counts. Only the GitHub adapter reads a milestone today
([`CONTRACT.md`](../../../tools/work-item-tracker/CONTRACT.md), "JSON output contract"),
so on another adapter nothing is cordoned.

## Post-snapshot intake report (every drain exit)

On **every** drain stop, ordinary drain completion and drain-terminal alike, the final report
**names the intake that arrived after the snapshot and was left unworked**. That report is what
keeps "reported, never chased" true once there is no next cycle to sweep it. Compute that list once,
after the exit verdict is already decided, by repeating step 1's **open-items** reading,
lane-infrastructure exclusion and all, per `SKILL.md`, and diffing it against the retained ids. Not
a `list-frontier --autonomous` reading: step 2's sweep hardening routes bot-authored advisory intake
to the human-gated role, which is precisely what that filter excludes, so the frontier reading would
report nothing in the case this sentence exists for. **The read is reporting-only and can never
change the verdict it follows.**
