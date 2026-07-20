# Runner escalation

Every runner stop is a terminal state, and every non-success terminal state hands the work
back to a human through the one governed queue. This leaf resolves the escalation UX the
[hub](../runner.md) routes here: the terminal-handoff shape, the two-family stop-criteria
taxonomy, the deterministic mapping from a stop to a severity-routed escalation item, and the
acknowledgment and re-escalation knobs. It defines only runner-new content; the inherited
escalation event classes, routing obligation, and one-channel invariant are cited from the
[guardrail escalation contract](../guardrails.md#escalation), never restated.

## Terminal handoff at launch

The launch escalation shape is terminal handoff: the runner runs each leased item to a
terminal state and never pauses mid-run for a human. Every stop resolves to exactly one
terminal outcome, carried in the structured-output envelope's `outcome` field
([envelope seam](seams.md)):

| `outcome` | Meaning |
|---|---|
| `success` | the item drained clean — gates passed, disposition applied |
| `gate-failed` | a blocking verification gate failed |
| `needs-human` | the run cannot proceed without human judgment or intervention |
| `cap-exceeded` | a turn, budget, or wall-clock cap bounded the drain before completion |

**Non-success outcomes file the escalation item.** `gate-failed`, `needs-human`, and
`cap-exceeded` each file a human-gated work item on the governed queue carrying the evidence
bundle: a failure summary, the run-transcript link, the run cost, the trace link, and the
`resume_handle`. Human takeover is not a distinct API — it resumes the persisted session behind
the `resume_handle` ([session-and-resume seam](seams.md)), so the escalation item is a
resumable takeover, not a cold restart.

**`success` never escalates — the runner's own outcome.** A successful outcome completes
through the normal path — the per-item disposition ([lifecycle leaf](lifecycle.md)) and the
task-boundary return-accounting capture ([return-accounting](../return-accounting.md)) — with
no runner escalation item and no acknowledgment or re-escalation obligation. Escalation is the
non-success path only; if a healthy drain filed escalation work, every clean run would generate
a false human task.

**Inherited always-firing classes are untouched by the success exception.** An event class the
[guardrail escalation contract](../guardrails.md#escalation) fires unconditionally —
`untrusted-provenance` on every `C5` item — fires regardless of outcome, success included: the
runner emits it before the run completes, and the resulting item and fan-out follow that
class's own route and severity, not the runner outcome mapping. The success exception
suppresses only the runner's own outcome escalation, never an inherited class's standing
obligation.

## Stop-criteria taxonomy — two families

A stop belongs to one of two families. The family determines who detects the stop, not its
severity — severity is resolved by the mapping below.

- **`runner-owned` (deterministic).** The runner detects these itself, without agent judgment:
  turn, budget, or wall-clock cap reached; execution error persisting after retries; model
  refusal; verification-gate failure; isolation violation; missing plan approval (a `C4`
  structural run leased without its recorded approval —
  [lifecycle leaf](lifecycle.md#c4-pre-execution-plan-approval)). Each is an observable runner
  condition, not a signal the agent has to raise.
- **`agent-signaled` (judgment).** The executing agent raises these through the envelope's
  `stop_reason` field, because only the agent holds the context to recognize them: ambiguity
  (multiple valid interpretations), a design decision needing human judgment, a
  security/data-integrity event, an unresolvable blocker, and no-progress (a stuck loop making
  no forward movement).

**Transient-recoverable never escalates.** A transient, recoverable condition — a rate limit,
a retryable execution error, a rescheduled run — is retried with backoff and is not a stop.
Only exhaustion of the retry budget converts it into a `runner-owned` execution-error stop.

## Severity resolution — the two-step mapping

Severity routing keys on the escalation *event class*. A runner outcome alone never names an
event class, and a stop reason never names its outcome, so resolution is a deterministic two
steps: stop reason to terminal outcome, then outcome to event class. Every non-success stop
traces the full path stop reason → outcome → event class → severity → route.

### Step one — stop reason to terminal outcome

| Family | Stop reason | `outcome` |
|---|---|---|
| `runner-owned` | verification-gate failure | `gate-failed` |
| `runner-owned` | turn / budget / wall-clock cap | `cap-exceeded` |
| `runner-owned` | execution error after retries | `needs-human` |
| `runner-owned` | refusal | `needs-human` |
| `runner-owned` | isolation violation | `needs-human` |
| `runner-owned` | missing plan approval (`C4`) | `needs-human` |
| `agent-signaled` | ambiguity | `needs-human` |
| `agent-signaled` | design decision needing human judgment | `needs-human` |
| `agent-signaled` | security/data-integrity event | `needs-human` |
| `agent-signaled` | unresolvable blocker | `needs-human` |
| `agent-signaled` | no-progress | `needs-human` |

### Step two — terminal outcome to event class

| `outcome` | Event class | Provenance |
|---|---|---|
| `gate-failed` | `gate-failure` | the [guardrail contract's](../guardrails.md#escalation) existing gate-failure class — reused, not re-minted |
| `needs-human` | `runner-needs-human` | runner-new, registered additively |
| `cap-exceeded` | `runner-cap-exceeded` | runner-new, registered additively |

`gate-failed` routes through the guardrail contract's own gate-failure event class; only
`needs-human` and `cap-exceeded` introduce new classes. The two runner classes
`runner-needs-human` and `runner-cap-exceeded` extend the escalation event-class registry
additively, alongside the guardrail contract's set — the security binding accepts route and
severity bindings for them exactly as it does for any guardrail event class, and existing
bindings validate unchanged. Their contract-default severities are `attention` and `notice`,
both org-bindable.

**Runner launch precondition.** Both runner classes' queue routes are part of the runner's
required governance: at launch the runner verifies that `runner-needs-human` and
`runner-cap-exceeded` each carry a bound `escalation_routes` entry, and fail-closes — blocking
dispatch — when either is absent, exactly as it does for an absent security binding
([topology leaf](topology.md)). Every non-success stop maps to one of these classes, so a
runner without their routes would have no queue destination for its required human-gated
handoff. The requirement binds the RUNNER, not the binding: a binding without the runner keys
stays valid for every pre-runner surface, which is why the static checker cannot enforce this
(no binding key says a runner is enabled) and the launch gate does.

## Severity axis and notification fan-out

Every event class escalates at a severity on a three-level axis — `notice`, `attention`,
`urgent` — that maps to org-bound notification fan-out over the single filed item. The fan-out
is notification depth on the one queue item, not a second escalation channel; the one-channel
invariant ([guardrail escalation contract](../guardrails.md#escalation)) holds.

| Severity | Fan-out |
|---|---|
| `notice` | the tracker item only |
| `attention` | tracker item + channel notification per the org route |
| `urgent` | tracker item + channel notification + a personal-push tier, org-bindable |

The tracker item is always filed; channel notification and the personal-push tier are
org-bound routes, and each leg exists only where its route is bound. An unbound leg degrades
the fan-out toward the always-filed tracker item — an org with no push adapter legitimately
binds `urgent` with the channel leg alone, and absent a bound channel adapter fan-out degrades
to tracker-item-only; degradation never drops the escalation item itself. The one rejected
shape is the inverse: a push leg bound without the channel leg beneath it, because the ladder
is cumulative and the push tier rides on top of the channel notification.

### Contract-default severities

Fan-out is fully defined with no `escalation_severity` binding present at all: every event
class carries a contract-default severity, each an org-bindable override.

| Event class | Default severity |
|---|---|
| `gate-failure` | `attention` |
| `verification-divergence` | `attention` |
| `admission-rejection` | `notice` |
| `demotion` | `attention` |
| `structural-plan-approval` | `attention` |
| `untrusted-provenance` | `urgent` |
| `runner-needs-human` | `attention` |
| `runner-cap-exceeded` | `notice` |

The six inherited classes are owned by the [guardrail escalation contract](../guardrails.md#escalation);
their default severities are assigned here so runner fan-out is defined for every class it can
route, without requiring an org to bind one first.

### Urgent stop-reason override

Two stop reasons carry an `urgent` severity override that sits on top of the event-class
default: an **isolation violation** and a **security/data-integrity event**. Both resolve to
`needs-human` → `runner-needs-human`, whose default severity is `attention`; the override
forces the filed item to `urgent` regardless of that default. The override keys on the stop
reason, not the outcome or the event class — a `needs-human` stop from any other reason keeps
the `attention` default.

## The filed escalation item

The filed item's envelope records both the resolved event class and the originating stop
reason, so a reader recovers the full trace from the item alone: which class routed it, and
which condition raised it.

**Acknowledgment and re-escalation.** An escalation item carries an acknowledgment state. An
unacknowledged item that goes stale re-escalates once with a one-level severity bump; an
acknowledged item never re-escalates. The bump saturates at `urgent`: an item already at
`urgent` — an untrusted-provenance default, or either urgent stop-reason override — still
re-escalates once, by re-notifying with a fresh `urgent` fan-out at the same severity, never by
skipping the re-escalation or minting a level above the axis. Both knobs are org-bindable: the
default staleness window is 72h, and the re-escalation cap is 1 (a single bump, never a loop).

## Deferred — mid-run interrupt

A mid-run interrupt shape — pausing the run to await human input before it reaches a terminal
state — is deferred. Its adoption trigger is evidence that kill-and-resume loses material cost
or context on real drains; until then, terminal handoff with a resumable session is the whole
escalation surface. First-party pause-and-resume mechanisms exist and are re-verified at build,
so adopting the interrupt shape later needs no change to this contract.

## Escalation telemetry

No standard telemetry signal for "an agent escalated to a human" exists, so escalation events
ride the [telemetry contract's](../telemetry.md) governed custom-namespace mechanism under the
work-item join attribute. The exact namespace token is read from the shipped telemetry contract
at build, not pinned here. A standard escalation signal is noted as a candidate upstream
contribution when the relevant conventions mature.

## Research gaps carried

The following are unresolved at design time and carried openly rather than closed by assumption:

- CI-action-class failure-reporting specifics — whether a failure surfaces as a comment, a
  check result, or a job failure — are UNVERIFIED; bind the exact reporting surface at build
  from live docs.
- Cross-vendor agent-needs-human signaling — the agent-protocol and agent-instruction-file
  guidance for how an agent raises a needs-human stop across surfaces — is UNVERIFIED; bind at
  build.
- Managed-agent event names drift between the stream surface and the webhook surface; bind the
  exact event names at build from live docs rather than pinning them here.
- No maintained, credible approval-as-a-service precedent exists — the once-cited approval SDK
  is deprecated and is never treated as living precedent.
