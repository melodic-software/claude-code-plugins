---
name: formal-claim-protocol
description: "TLA+ model of the work-item tracker's GitHub claim protocol: one issue claimed at once by a local session's default claim, the issue lane's lease-only claim and a triage claim, each able to renew once and release, with lease expiry, the 300 s skew margin, the completed-run rule and the assignee hand-back. Use when a change touches the GitHub adapter's claim.sh, renew-lease.sh, release.sh, common.sh, lib/lease.sh or the tracker contract's Lease protocol, or to ask whether two claimants can both work one item."
disable-model-invocation: true
---

# Formal check: the claim protocol

## Property

Each rule is an INVARIANT in `model/ClaimProtocol.tla`; the quoted line is the source it encodes.
Paths are under `plugins/work-items/tools/work-item-tracker/`.

| Rule | Plain sentence | Source |
|---|---|---|
| `OneHolder` | At most one claimant works the item while its own lease is live. | `CONTRACT.md` "Lease protocol" step 4: "If an earlier live lease exists that is not our own comment, the foreign lease wins → supersede own comment, exit `7`."; `adapters/github/claim.sh`: "# Earliest LIVE lease wins." |
| `LaneAssignsNoOne` | The issue lane's lease-only claim never assigns anyone. | CONTRACT.md: "**Lease-only (`--lease-only`):** the claim posts the lease comment and assigns no one." |
| `HolderAssigned` | A default claimant that holds the item is assigned to it. | CONTRACT.md: "Claim = **assignee (authenticated human user) + lease record**." |
| `NoStrandedAssignee` | Every assigned login belongs to a claim still in flight. | `adapters/github/claim.sh`: "any failure before a successful lease-comment write (step 3) would otherwise strand the issue assigned with no lease record" |
| `LoserSupersedesOwn` | A claimant that lost arbitration has superseded its own lease. | CONTRACT.md step 4: "the foreign lease wins → supersede own comment, exit `7`." |
| `CompletedRunHoldsNothing` | No claimant backs off from a lease whose run had completed. | CONTRACT.md step 4: "A run whose `status` is `completed`, whatever its conclusion, holds nothing, so its lease is superseded in place" |
| `ReleaseFreesItem` | A claimant that released no longer holds a live lease. | CONTRACT.md, Release: "a session that has finished with an item hands it back at once instead of blocking every later claim" |

How each rule reads the model's states:

- "Works the item" (`Holding`): the claim returned success, no release returned success, no renew
  told the session it lost or is still re-checking after a late renew, and its own lease is live.
- `HolderAssigned` is checked in quiescent states only (every claimant holds, has finished, or has
  not started): the hand-back removes and restores a same-login holder's assignee two calls apart.
- "In flight" (`NoStrandedAssignee`): a default claimant of that login has started and not
  returned: it is claiming, holds the item, or is renewing, releasing or handing back.
- `LoserSupersedesOwn` covers a claimant that lost, failed or died; it assumes writes succeed,
  since the supersede is best-effort.
- `CompletedRunHoldsNothing` records the moment a claimant's decision goes against the lane's
  lease while the lane's run has completed.

`TypeOK` checks the variables' types. `EndStateReclaimable` is an extra rule: once every claimant
has finished and no lease is live, any assignee left is the holder of the active lease, which
reclaim unassigns.

## Harm

Two sessions work the same issue at once and push conflicting changes, or an issue stays assigned
with nobody working it and drops off the frontier.

## Tool and why

TLA+ with TLC, read through `/formal-verification:chart`. The question is whether the GitHub calls
of three sessions can interleave into a bad order; a model checker tries every order of a small
model, and the races live between comment, assignee and clock reads that no unit test sequences.

## Bounds and assumptions

- One issue; three claimants: `local` (login `human`), the lane (holder `bot`, `--lease-only`,
  `session_id` `run-<id>`) and `triage` (login `human` or `other`; both are explored). The cfg's
  `Starters` names the claimants that start a claim.
- Each claimant claims once, renews at most once (`WithRenew`) and releases at most once; at most
  three lease comments; one renewal generation per lease.
- Every GitHub read and write is its own step. A lease list retried once is one step.
- One clock for every claimant: entering the 300 s margin and expiring are global events per lease.
  With `BoundedStall`, a body read more than 300 s before its expiry is judged before it expires,
  and a renew that judged its lease outside the margin PATCHes before it expires.
- Lease comment ids grow in posting order.
- The lane's run can end at any point after its lease is posted, without releasing.
- Failures are off unless a cfg turns them on: `WritesMayFail` (each best-effort write may fail),
  `ReadsMayFail` (the reads whose failure does not exit may fail), `MayDie` (a claimant may die
  between any two steps; a checked call's failure exits the same way). `RenewDeathKeepsHolding`
  is `FALSE`: a renew that dies after its PATCH ends the session.
- The cfg uses `VIEW View`, which drops script-local values a claimant never reads again. Under
  it TLC's distinct-state count depends on exploration order; the chart command runs one worker,
  so its count is stable.
- No per-model bound is passed: the model is finite.
- The seeded break in `sync.yaml` was run against this model: with the winner taken as the latest
  live lease, `OneHolder` breaks in `LocalLane.cfg` after 1,415 distinct states (`caught: true`).

## Not covered

- Reclaim, the local-markdown and other adapters, the role-label flip, a second renew, and an
  assignee a person adds by hand.
- A comment from an author the adapter does not count, a cross-issue or foreign handle, and
  `gh api user` reads.
- Time passing between renew's PATCH and its clock read after it: the model takes both in one
  step, so it never shows a renew that landed in time but reads its clock inside the margin or
  past the old expiry (the code then re-lists or backs off).
- A PATCH that GitHub applies but reports as failed (renew's or release's), a lease
  `renewed_at` more than 300 s in the future, a TTL over the cap, and the pause between writes.
- Three sessions on one login: the model has at most two. With three, a hand-back's last removal
  can land after a third session's claim won, leaving that holder unassigned (issue 16505).
- `WithRenew = TRUE` with all three claimants: that space is over 100 million states. The shipped
  checks run two claimants each; the three-claimant space is checked without renew only by hand.
- The tracker contract's documented limits are reported as known limits, never as defects:
  clock skew ("Liveness compares provider timestamps (`renewed_at` in the marker) to the local
  clock"), ttl-0 ("A claim with `ttl_hours: 0` and `ttl_minutes: 0` is born expired"),
  comment-id monotonicity ("adapters MUST emit ordered unique numeric `lease_comment_id`
  handles"), the ambiguous lease post ("A lease comment POST that GitHub applies but reports as
  failed (a timeout) returns no comment id"), and no compare-and-swap ("GitHub's comment PATCH
  has no If-Match/CAS, so a concurrent writer can still interleave").

## Run

One command per cfg; each takes about 90 s:

```text
/formal-verification:chart .claude/skills/formal-claim-protocol/model/ClaimProtocol.tla --config .claude/skills/formal-claim-protocol/model/LocalLane.cfg --view .claude/skills/formal-claim-protocol/model/view.mjs --rerun-states 1000000
/formal-verification:chart .claude/skills/formal-claim-protocol/model/ClaimProtocol.tla --config .claude/skills/formal-claim-protocol/model/LocalTriage.cfg --view .claude/skills/formal-claim-protocol/model/view.mjs --rerun-states 1000000
```

`LocalLane.cfg` runs the local session against the issue lane, `LocalTriage.cfg` the local session
against a triage claim; both with renew, every failure off and `BoundedStall`. `--rerun-states`
must cover the whole space (746,798 and 540,596 states): after a rule breaks, the command rechecks
the others under that bound, and a smaller bound leaves them not checked.

Pass a new `--out` folder each run.

## Reading a result

Replay each counterexample step by step against the scripts on a scratch issue, one call per
action. The actions are named for the calls they model: `Assign`, `CheckRead`, `ReAssign`,
`PostLease`, `ReadLeases`, `ArbJudge`, `ArbRunRead`, `ArbRunSup`, `LossSup`, `WinRead` and
`WinAdd` are `claim.sh`; `RenewStart`, `RenewPatch`, `Ren2Leases`, `Ren2Judge` and `RenSup` are
`renew-lease.sh`; `ReleaseStart`, `RelJudgeOwn` and `RelPatch` are `release.sh`; `GLeases` to
`GRm3` are the hand-back, `wit_hand_back_assignee` in `common.sh`; `TrapSup` is claim's abort
trap; `Die` is a death or an exiting failure; `RunCompletes`, `Approach` (300 s before expiry) and
`Expire` are the world. Each action's comment in the model cites its lines. If a bug does not
occur, think that the model is wrong until you show that it is not. A path that reproduces is a
bug: write it up with `/bugs:write`. A path that needs a documented limit to fail is reported as
that limit.

Known results at the sync commit (a run that shows only these has found nothing new):

- `NoStrandedAssignee` breaks in both cfgs. A lease near expiry is renewed while a newer
  claimant judges it expired and wins (the renew's re-list then backs off, by design); the winner
  releases while the renewed lease is still live, and the release is refused as outranked
  (`release.sh` exits 7 with no hand-back). Its login stays assigned with its live lease until the
  TTL, then reclaim removes it (`EndStateReclaimable` holds). By design: CONTRACT.md, Release:
  "Anything else is refused with exit `7` and no lease is written: ... a live handle an earlier
  live lease outranks".
- `HolderAssigned` breaks in `LocalTriage.cfg` with one login on both sessions: a release's
  hand-back removes the login, re-lists the leases while the other session's lease is within
  300 s of expiry, that session's renew lands, the old expiry passes, and the hand-back judges the
  listed body with a clock read after the expiry, so it does not put the login back. The holder
  works unassigned. A known limit (a stall between a read and its clock sample, no
  compare-and-swap); CONTRACT.md does not state it for the hand-back.
- With `ReadsMayFail = TRUE`, `OneHolder` breaks: renew's re-list after a PATCH inside the margin
  fails twice and the renewed lease is kept while a newer claimant holds. By design: "a list it
  still cannot read keeps the renewed lease (exit `0`, with a warning)". `CompletedRunHoldsNothing`
  breaks there too: "A run in any other status, or a read that fails, keeps the lease winning."
- With `MayDie = TRUE`, `NoStrandedAssignee` and `EndStateReclaimable` break (a claim killed
  during its own rollback leaves its assignee with no lease, which reclaim ignores), and in
  `{"local","triage"}` `HolderAssigned` breaks (a same-login hand-back killed between its removal
  and its re-list). A known limit: a killed process cannot finish its exit trap.

## Updating

When a covered file in `sync.yaml` changes, read the change against the model: a call split in
two, a new branch, a retry, or a moved check means the model changes; a promise changed on purpose
means a rule changes, and only with the owner's yes. Never weaken a rule to make it hold. Move
`commit` forward only after confirming the model describes the code at the new commit, re-cite
the changed line numbers in the model's comments, rerun every shipped cfg and the seeded break,
and update the known results above.
