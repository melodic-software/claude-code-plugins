# Runner lifecycle

The runner's handling of a single leased work item is a linear state machine:
`leased → executing → verifying → disposing → (escalated | complete)`. Each state's work is
owned by a seam in [the seam set](seams.md); this leaf fixes the state model and the telemetry
every transition emits, and defers the terminal-outcome and severity vocabulary to
[the escalation leaf](escalation.md). It defines only lifecycle-new content — every inherited
obligation is cited from its owning contract, never restated here.

## State model

One item occupies one state at a time; the machine is linear with a single terminal branch.
Two states are terminal: `escalated` and `complete`.

| State | The runner, on entry | Owning seam / contract (cited) |
|---|---|---|
| `leased` | Claims one item through the race-safe lease — one leased item to one emitting session, no second claim path. | [queue and lease](seams.md#queue-and-lease) → [dispatch](../trigger-dispatch.md#dispatch) |
| `executing` | Runs the item in isolation at or above its class's floor; an unattestable or unbound substrate fail-closes rather than degrading. | [isolation policy](seams.md#isolation-policy) → [matrix](../guardrails.md#the-matrix), [isolation ladder](../guardrails/isolation-ladder.md) |
| `verifying` | Runs the class's verification layers and resolves a pass/fail result into the envelope. | [outcome-verification gate](seams.md#outcome-verification-gate) → [matrix](../guardrails.md#the-matrix) |
| `disposing` | Applies the per-class merge policy to a passing result (see [disposition](#disposition) below). | [merge-policy toggle](seams.md#merge-policy-toggle) → [matrix](../guardrails.md#the-matrix) |
| `escalated` | Terminal. Files the human-gated handoff; the terminal outcome and severity vocabulary are the escalation leaf's. | [escalation](escalation.md) |
| `complete` | Terminal. The disposition landed; the run closes through the return-accounting capture at the task boundary. | [observability and cost](seams.md#observability-and-cost) → [return-accounting](../return-accounting.md) |

A stop at any non-terminal state resolves to `escalated` rather than advancing; the mapping
from a stop reason to its terminal outcome is [the escalation leaf](escalation.md)'s subject.
Only a run that reaches `disposing` and lands its change becomes `complete` — every other
ending is `escalated`.

### C4 pre-execution plan approval

A `C4` (structural) item never travels `leased → executing` into structural work on ordinary
admission alone: the [guardrail escalation contract](../guardrails.md#escalation) fires its
`structural-plan-approval` event class for a `C4` item BEFORE execution, and the runner honors
that as a two-phase drain through the one queue. The first leased run plans only — its
disposition is the `structural-plan-approval` item (the inherited class, on its own route and
severity, with the produced plan attached), and it completes without touching the structure.
The structural execution is a second run, admitted only from the human-approved item; its
`leased → executing` transition requires that recorded approval, and absent one the run
fail-closes to `escalated` rather than executing. No second approval channel exists — the
approval item is ordinary human-gated queue work, and the terminal-handoff shape
([escalation leaf](escalation.md)) is untouched: neither phase pauses mid-run.

## Transition telemetry

Every transition emits standard telemetry carrying the work-item join attribute and the
propagated trace context, so the whole run is one branch of the one causal tree and the runner
adds no parallel schema. Emission, the join attribute, and trace propagation are the
[telemetry contract](../telemetry.md)'s, driven through the
[observability seam](seams.md#observability-and-cost) — cited, never restated here. The
`escalated` transition additionally carries escalation telemetry on the telemetry contract's
custom-namespace mechanism; that namespace token, and the escalation payload, are
[the escalation leaf](escalation.md)'s.

## Disposition

Launch disposition is thin and follows the class's
[matrix merge-policy row](../guardrails.md#the-matrix):

- A read-only class — `C1`, whose merge row is not applicable and whose definition forbids
  repository mutation — never opens a PR: its passing result completes by attaching the
  produced artifact or report to the governed queue item, the audit trail the matrix names as
  `C1`'s disposition surface.
- A mutating class lands as a per-item PR through the platform's native change-proposal flow —
  one item, one PR, no runner-owned merge machinery. Who lands it is the class's merge-policy
  cell: an auto-merge only where that cell is promoted AND the run is self-run; human-gated
  everywhere else.

The vendor-hosted merge cap is restated here, not inherited silently: whenever the executing
backend is a vendor-hosted executor, every class caps at human-gated regardless of its self-run
merge row, so the auto-merge disposition path is reachable only on a self-run backend.
[The topology leaf](topology.md) carries the same cap on the cloud-backend selection.

### Growth stage — batched gated-merge serialization

Deferred, with an evidence trigger: observed concurrent auto-merge collisions on the platform's
native flow. When that evidence arrives, the runner serializes gated merges by binding a
platform-native merge-queue facility where one exists — never a reimplemented queue. That
facility's availability is verified at binding time; absent one, the growth stage stays
deferred rather than reimplementing a built-in. No serialization ships at launch.
