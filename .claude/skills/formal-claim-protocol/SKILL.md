---
name: formal-claim-protocol
description: "TLA+ model of the work-item tracker's GitHub claim protocol: one issue claimed at once by a local session's default claim, the issue lane's lease-only claim and a triage-phase claim, with lease expiry, release and the completed-run rule. Use when a change touches the GitHub adapter's claim.sh, release.sh, lib/lease.sh or the tracker contract's Lease protocol, or to ask whether two claimants can both work one item. DRAFT: its invariants wait for the owner's approval before the model is checked."
disable-model-invocation: true
---

# Formal check: the claim protocol

**Status: draft.** The invariants under Property are drafted, each with the line it encodes. The
owner approves the list before the model is checked; until then no result exists, and
`sync.yaml`'s seeded break is recorded as not yet caught.

## Property

Each rule is an INVARIANT in `model/ClaimProtocol.tla`; the quoted line is the source it encodes.

| Rule | Plain sentence | Source |
|---|---|---|
| `OneHolder` | At most one claimant works the item while its own lease is live. | `plugins/work-items/tools/work-item-tracker/CONTRACT.md` "Lease protocol" step 4: "If an earlier live lease exists that is not our own comment, the foreign lease wins → supersede own comment, exit `7`."; `adapters/github/claim.sh`: "# Earliest LIVE lease wins." |
| `LaneAssignsNoOne` | The issue lane's lease-only claim never assigns anyone. | CONTRACT.md: "**Lease-only (`--lease-only`):** the claim posts the lease comment and assigns no one." |
| `HolderAssigned` | A default claimant that holds the item is assigned to it. | CONTRACT.md: "Claim = **assignee (authenticated human user) + lease record**." |
| `NoStrandedAssignee` | Every assigned login belongs to a claim still in flight. | `adapters/github/claim.sh`: "any failure between this successful assignment and a successful lease-comment write (step 3) would otherwise strand the issue assigned with no lease record" |
| `LoserSupersedesOwn` | A claimant that lost arbitration has superseded its own lease. | CONTRACT.md step 4: "the foreign lease wins → supersede own comment, exit `7`." |
| `CompletedRunHoldsNothing` | No claimant backs off from a lease whose run had completed. | CONTRACT.md step 4: "A run whose `status` is `completed`, whatever its conclusion, holds nothing, so its lease is superseded in place" |
| `ReleaseFreesItem` | A claimant that released no longer holds a live lease. | CONTRACT.md, Release: "a session that has finished with an item hands it back at once instead of blocking every later claim" |

`TypeOK` checks the variables' types only.

## Harm

Two sessions work the same issue at once and push conflicting changes, or an issue stays blocked
with nobody working it.

## Tool and why

TLA+ with TLC, read through `/formal-verification:chart`. The question is whether claim steps from
three sessions can interleave into a bad order, which a model checker answers over every order of a
small model; the race lives in comment and assignee writes no unit test sequences.

## Bounds and assumptions

- One issue, three claimants, each claiming at most once; at most three lease comments.
- The triage session's login is either the local session's login or another (both are explored).
- A claimant's step 4 (read the leases, read the run status, decide) is one indivisible step.
- Lease comment ids grow in posting order.
- Every lease has a TTL above zero, and every claimant reads the same clock: expiry is one global
  event per lease.
- The lane's run can end at any point after its lease is posted, without releasing.
- No per-model bound is passed: the model is finite.
- The seeded break in `sync.yaml` has not been run (`caught: false`).

## Not covered

- Renew, reclaim, the local-markdown and other adapters, and the role-label flip.
- A failed GitHub read or write, the rollback trap's timing, and an author whose lease comment the
  adapter does not count.
- The tracker contract's three documented limits are reported as known limits, never as defects:
  clock skew ("Liveness compares provider timestamps (`renewed_at` in the marker) to the local
  clock"), ttl-0 ("A claim with `ttl_hours: 0` and `ttl_minutes: 0` is born expired"), and
  comment-id monotonicity ("adapters MUST emit ordered unique numeric `lease_comment_id` handles").

## Run

```text
/formal-verification:chart .claude/skills/formal-claim-protocol/model/ClaimProtocol.tla --view .claude/skills/formal-claim-protocol/model/view.mjs
```

The config is `model/ClaimProtocol.cfg`, beside the spec. Pass a new `--out` folder each run.

## Reading a result

Replay each counterexample step by step against `adapters/github/claim.sh` and `release.sh` on a
scratch issue, one step per action: `Assign`, `CheckAssignees`, `Post` and `Arbitrate` are claim
steps 1 to 4, `Release` is the caller clearing its assignee then `release`, `RunCompletes` is the
lane's run ending, and `Expire` is a lease's TTL passing. If a bug does not occur, think that the
model is wrong until you show that it is not. A path that reproduces is a bug: write it up with
`/bugs:write`. A path that needs one of the three known limits to fail is reported as that limit.

## Updating

When a covered file in `sync.yaml` changes, read the change against the model: a step split in two,
a new branch, or a moved check means the model changes; a promise changed on purpose means a rule
changes, and only with the owner's yes. Never weaken a rule to make it hold. Move `commit` forward
only after confirming the model describes the code at the new commit, and record the seeded break
the check caught.
