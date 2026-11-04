# Guardrails

Normative contract for per-work-class guardrail enforcement: five semantic risk classes
(`C1`–`C5`) crossed with six guardrail columns, in one matrix. This document is the hub and
glance layer of a progressive-disclosure contract. The matrix plus the one-line class and
column definitions below alone answer "what governs class X"; every deeper question routes to
a named leaf under `guardrails/`, loaded on demand. Vocabulary is contract-owned; every
concrete instance (isolation substrates, review tooling, model names, escalation routes) is an
org-binding outcome on the binding seam.

## The matrix

The matrix instantiates the Boris playbook's step-4 sentence verbatim, "enforcing the right
guardrails for each type of work", as a table: one row per work class, one column per
guardrail axis. That sentence is the playbook's; the five-class taxonomy, the per-layer
blocking knobs, and the promotion predicates that fill the cells are this contract's own
instantiation of it. The playbook names the obligation, and this contract supplies the mechanism.

| Class | Min isolation (unattended) | Verification | Verification topology | Merge policy | Cost tier | Escalation |
|---|---|---|---|---|---|---|
| C1 | L2 (exfil surface remains) | output-shape checks | 1 checker | n/a; artifacts via queue audit trail | economy | low |
| C2 | L2 | deterministic blocking | 1 checker | auto-merge ELIGIBLE after per-class promotion trigger; ships human-gated | economy | gate failure → owning lane |
| C3 | L2 | deterministic blocking + AI review (advisory, promotable per [the security-review policy](guardrails/security-review.md)) | 2 distinct checkers, 1 a model judge | auto-merge ELIGIBLE after per-class promotion trigger; ships human-gated | standard | divergence/failed verify → owning lane |
| C4 | L2 | deterministic blocking + AI review blocking | 3 distinct checkers, 2 vendor-disjoint model judges | auto-merge ELIGIBLE after the `C3-auto-merge` promotion; ships human-gated | premium | divergence/failed verify → owning lane |
| C5 | L3 | full gates + zero secret exposure | 3 distinct checkers, 2 vendor-disjoint model judges | human merge always | standard | always |

### Classes

- `C1` read-only: audits, research, reports; no repository mutation (governed-queue and
  tracker writes are permitted output, with the scoping in the leaf).
- `C2` mechanical maintenance: dependency bumps, lint/format, sync; deterministic and
  trivially reversible.
- `C3` scoped change: a briefed fix or small feature; bounded, tests exist.
- `C4` structural: refactors, migrations, contract changes; cross-cutting, hard reversal.
- `C5` untrusted-provenance: fork PRs, external contributions, unvetted repositories, and
  items carrying the `provenance: signal` label.

### Columns

- **Min isolation (unattended)**: the isolation-ladder level (`L0`–`L3`) that is the floor
  for running the class unattended. On the ladder's
  [CI-lane surface](guardrails/isolation-ladder.md#ci-lanes-on-provider-hosted-runners), its
  five conditions stand in for `L2` while they all hold; `C5` keeps `L3`.
- **Verification**: the gate layers a change must pass, with per-layer blocking knobs bound
  on the governance surface.
- **Verification topology**: the floor for how many DISTINCT checker slots verify the class
  and whether they must be vendor-disjoint; roles, relational constraints, and predicates are
  contract vocabulary, instances org-bound. The leaf owns these floor values; the cells above
  are their glance restatement.
- **Merge policy**: who lands the change; promotion-gated where the cell says so. A merge
  authority that reads no class merges on its verifier verdict instead
  ([work classes](guardrails/work-classes.md#merge-authorities-that-read-no-class)), and still
  never merges `C5`.
- **Cost tier**: contract vocabulary (`economy` | `standard` | `premium`); the org binds
  tiers to model instances. Policy vocabulary only. Cost enforcement is out of scope.
- **Escalation**: where a run hands an event: to the lane that owns the follow-up, or to a
  person only under the stop rule below; event classes and routing below.

## Glance-layer rule

The matrix and the one-line definitions above are the whole glance layer: they alone answer
"what governs class X". Every deeper question routes to a named leaf, and depth is never
answered from this document:

| Deeper question | Leaf |
|---|---|
| What each level means, which substrate classes satisfy it, what happens when none does | [isolation-ladder](guardrails/isolation-ladder.md) |
| What exactly is in each class, and how a promotable cell promotes or demotes | [work-classes](guardrails/work-classes.md) |
| Which verification layers exist and which block, per class | [security-review](guardrails/security-review.md) |
| Which roles verify a class, how they must differ, and the shipped checker floors | [verification-topology](guardrails/verification-topology.md) |
| Which signals may enter the queue autonomously, and under what caps | [admission-policy](guardrails/admission-policy.md) |
| Per-invocation merge widening (`autopilot` + `--merge c3-this-run`) | The `source-control` plugin's config-resolution reference, § typed pair exception |

## Per-invocation merge widening

The matrix's merge-policy column describes **standing** authority: promotion-gated cells that
require a recorded, team-tracked adoption before auto-merge is eligible. Separately, the
`source-control` babysit-loop lane defines **one named per-invocation exception**: an argument
line that types both the literal `autopilot` tier keyword and `--merge c3-this-run` widens
*that single invocation's* merge dimension up to and including C3, still bounded by the C5
untrusted-provenance hold.

This exception is not a matrix promotion and is never persisted. The next invocation without
the pair reverts to the tracked `babysit_loop_merge` resolution. No config layer supplies either
token; both must appear on the invocation line. The full contract (baseline adoption requirement,
mutual exclusivity with safer `--merge` values, and the C5 hold) lives in the `source-control`
plugin's config-resolution reference, at `reference/config-resolution.md` inside that plugin.

## Permission posture

Permission posture is not a matrix column: `L1` is the attended ergonomics tier where
per-action prompts remain the control; at `L2` and above the whole-process boundary is the
control, replacing per-action prompts. The [isolation-ladder](guardrails/isolation-ladder.md)
leaf carries this note in context.

## Automatic transitions

Unanimity is not a matrix column: every transition a run takes without a human, merge and
every stage before it, requires unanimous agreement among the checkers the class declares,
and one dissent withholds the transition and raises `verification-divergence` below.
It is a fixed invariant, not a knob, so no cell above can express it. The
[verification-topology](guardrails/verification-topology.md) leaf carries it in context,
including what is enforced at binding-validity time today and what is deferred.

## Escalation

Six escalation event classes:

| Event class | Fires when | Stops for a person |
|---|---|---|
| `gate-failure` | a blocking verification gate fails | only under the stop rule |
| `verification-divergence` | a verification outcome diverges from the expected or claimed result, or two checkers of one class disagree | only under the stop rule |
| `admission-rejection` | the admission seam rejects a signal as an audited rejection | only under the stop rule |
| `demotion` | contrary evidence automatically demotes a promoted cell | only under the stop rule |
| `structural-plan-approval` | an org-bound step asks a human to approve a `C4` item's plan; no shipped step raises it | only when the plan changes intent or the primary design |
| `untrusted-provenance` | always, for every `C5` item | always: a kept trust control |

**Stop rule.** An event class names what happened, not who acts on it. An event stops for a
person only when it carries one of three reasons: the original intent or vision changes, a
finding alters intent, vision or the primary design, or a HIGH or CRITICAL security or cost
risk. Any other event goes to the lane that owns the follow-up: a failed gate or a dissent to
the lane doing the work, and a demotion to its fix issues through intake, the cell re-earning
from run evidence ([work classes](guardrails/work-classes.md)). An audited rejection stays
final on the audit trail; a follow-up enters intake only as a new signal. A trust control the
org keeps, such as `untrusted-provenance`, stops for a person whatever the reason. An org
records its stop rule and kept controls in its own governance docs.

**Routing obligation.** Every event class has one org-bound route in the security binding: the
queue of the lane that owns its follow-up, or the human gate for a class that always stops.
The lane on that route applies the human-gated label only when a stop-rule reason or a kept
control applies. Escalation routes are a security-sensitive axis, so they bind on the
governance surface, and an absent or invalid binding fail-closes per the binding contract.

**Payload.** The work-item reference plus the trace link: every escalation carries the item
it concerns and the trace context joining it into the one causal tree, so the evidence behind
the escalation is queryable from the event.

**Mechanism.** The governed queue itself: an escalation lands as a work item on the one
queue, on its bound route, human-gated only when the stop rule or a kept control sends it to
a person, with an optional channel notification delivered through the trigger contract's
closed-loop acknowledgment symmetry ([trigger-dispatch](trigger-dispatch.md)).

**The one-channel invariant.** No second escalation channel exists. It is this contract's
own, distinct from and narrower than the claim and dispatch paths, which the
[one-entrypoint invariant](trigger-dispatch.md#dispatch) states canonically and which binds
here unchanged.

Escalation UX is specified by the [runner escalation leaf](runner/escalation.md): terminal
handoff at launch, with the mid-run interrupt shape deferred there behind its own trigger.
