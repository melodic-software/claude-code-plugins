# Mini-SDLC pipeline shape — the work lane's per-issue execution shape

The single source of truth for the **shape** of the per-item pipeline the `/work-items:work` lane is
being built to run: which lanes exist, the role-separation invariant they are to enforce, and how depth
(never shape) scales per item. `work` Step 5 points the dispatched chain at this document for that shape
instead of carrying its own workflow prose; the per-item *sizing* of these lanes is authored in the
item's plan, not here.

This document owns the durable **policy**. It is not a claim about what the runtime does today: the
staged work that wires each lane's full realization is tracked under `#513` (the mini-SDLC umbrella) —
this shape is the target those stages build to.

## Status — reference-doc STOPGAP

Form, location, and name are **not locked** (mini-SDLC umbrella `#513`, OPERATOR DECISION 1). This ships
as a reference doc so the policy has one home now, reversibly: it is promotable to a `work-items`
orchestration skill later without moving the policy. Revisit trigger: the operator ratifies the final
form. **If promoted to a skill, flag the naming collision** with `session-flow:orchestrate` and
`implementation:implement-dispatch` before choosing a skill name.

## Principle — variation in depth, never in shape

Every item traverses the **same** lanes in the same order. A trivial item and a sprawling one differ
only in the **depth** each lane runs at — never in which lanes run. A lane is never skipped; what
collapses is its *realization* (a dispatched fresh-context subagent → an inline lightweight check →
the consumer's own workflow step for that stage when no lane skill is installed; N rounds → one) down
to its minimum, but the lane itself always runs. Depth is the throughput lever; shape is invariant.

## The lane catalog

Each lane runs once per item, in this order. A lane is *composed from* the installed skill catalog —
the skills named are its reference realization (published as sibling plugins in this marketplace), not
a re-specification of their contracts. `work-items` installs standalone and hard-depends on none of
them: where a lane's skill is not installed, the lane is to degrade to the consumer's own workflow for
that stage (the Step 5 anchor) rather than dead-end.

| Lane | Composed from | What the lane owns |
|---|---|---|
| Explore | `discovery:explore` | Read the code and context the item touches before any change. |
| Research | `discovery:research` | Ground decisions in current authoritative sources, not recall. |
| Plan | `planning:plan` | Produce the approach, test strategy, and the per-item lane **sizing** this shape scales by. |
| Devil's advocate | `planning:devils-advocate` | Stress-test the plan's assumptions before implementation begins. |
| Implement | `implementation:implement` / `implementation:implement-dispatch` | Make the change; the implementer never reviews or verifies its own output. |
| Test | `testing:*`, `tdd:principles`, `toolchain:*` | Prove the change against a spec the implementer may not weaken. |
| Review | `review:code-reviewer` / `review:quality-gate` | Review the diff via a reviewer **distinct from the implementer**, before the PR opens. |
| Verify | `verification:*` | Confirm the result against evidence via a **fresh-context verifier**, distinct from the implementer. |

The **re-anchor slot** (`re-anchor:*`) is reserved: the re-anchor set is a periodic anchor across lane
execution rather than a human-invoked extra. Its placement in the sequence is left for a later `#513`
stage; this document reserves the slot and does not yet define its cadence.

## The separation invariant

**Implementer ≠ reviewer ≠ verifier.** Under this shape the agent that writes a change is not the agent
that reviews its diff, nor the agent that verifies its result: implement, review, and verify are
distinct roles, to be carried by distinct ephemeral fresh-context agents. This is the invariant the
whole shape exists to hold — the sizing may collapse a lane's depth, but it may never collapse two of
these three roles into one agent.

## Depth tiers

Depth tiers name **depth levels, not lane subsets** — a deeper tier runs every lane more thoroughly, a
shallower tier runs every lane more cheaply; no tier omits a lane. The tier **names** are placeholders
here (mini-SDLC umbrella `#513`, OPERATOR DECISION 2), left for the operator to ratify:

| Tier (placeholder) | Depth intent |
|---|---|
| `<tier-shallow>` | Each lane at minimum depth — inline lightweight checks, single-round. |
| `<tier-standard>` | Each lane dispatched, single-pass. |
| `<tier-deep>` | Each lane dispatched with fresh-context subagents and multiple rounds where the lane supports them. |

The tier for an item is **plan-driven with orchestrator override** — carried as a field in the item's
plan (not a label), matching the sizing heuristic settled in the `#513` ACCEPTED decision brief. The
dispatcher that reads the tier and sizes the worker chain is a later `#513` stage; this document defines
the tiers it reads.

## Contracts this shape composes

- **Return-payload contract** — `#496`: subagents in the chain return only identifiers, verdict, and
  parked-payload pointers upward; chatty coordination stays low in the chain. The dispatcher tier is to
  follow this contract when summarizing to the orchestrator.
- **Convention-gap protocol** — `#554`: when a lane hits a decision with no governing convention, the
  answer is never invent-and-proceed. Surface it, discuss, create the convention, human signs off
  (interim-unblock + tracked-convention-decision template).
