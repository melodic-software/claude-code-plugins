# Guardrails

Normative contract for per-work-class guardrail enforcement: five semantic risk classes
(`C1`–`C5`) crossed with five guardrail columns, in one matrix. This document is the hub and
glance layer of a progressive-disclosure contract — the matrix plus the one-line class and
column definitions below alone answer "what governs class X"; every deeper question routes to
a named leaf under `guardrails/`, loaded on demand. Vocabulary is contract-owned; every
concrete instance (isolation substrates, review tooling, model names, escalation routes) is an
org-binding outcome on the binding seam.

## The matrix

The matrix instantiates the Boris playbook's step-4 sentence verbatim — "enforcing the right
guardrails for each type of work" — as a table: one row per work class, one column per
guardrail axis. That sentence is the playbook's; the five-class taxonomy, the per-layer
blocking knobs, and the promotion predicates that fill the cells are this contract's own
instantiation of it — the playbook names the obligation, this contract supplies the mechanism.

| Class | Min isolation (unattended) | Verification | Merge policy | Cost tier | Escalation |
|---|---|---|---|---|---|
| C1 | L2 (exfil surface remains) | output-shape checks | n/a; artifacts via queue audit trail | economy | low |
| C2 | L2 | deterministic blocking | auto-merge ELIGIBLE after per-class promotion trigger; ships human-gated | economy | gate failure → human |
| C3 | L2 | deterministic blocking + AI review (advisory, promotable per [the security-review policy](guardrails/security-review.md)) | auto-merge ELIGIBLE after per-class promotion trigger; ships human-gated | standard | divergence/failed verify → human |
| C4 | L2 | deterministic + AI + human review mandatory | human merge always | premium | upfront plan approval |
| C5 | L3 | full gates + zero secret exposure | human merge always | standard | always |

### Classes

- `C1` read-only — audits, research, reports; no repository mutation (governed-queue and
  tracker writes are permitted output — scoping in the leaf).
- `C2` mechanical maintenance — dependency bumps, lint/format, sync; deterministic and
  trivially reversible.
- `C3` scoped change — a briefed fix or small feature; bounded, tests exist.
- `C4` structural — refactors, migrations, contract changes; cross-cutting, hard reversal.
- `C5` untrusted-provenance — fork PRs, external contributions, unvetted repositories.

### Columns

- **Min isolation (unattended)** — the isolation-ladder level (`L0`–`L3`) that is the floor
  for running the class unattended.
- **Verification** — the gate layers a change must pass, with per-layer blocking knobs bound
  on the governance surface.
- **Merge policy** — who lands the change; promotion-gated where the cell says so.
- **Cost tier** — contract vocabulary (`economy` | `standard` | `premium`); the org binds
  tiers to model instances. Policy vocabulary only — cost enforcement is out of scope.
- **Escalation** — when a run must summon a human; event classes and routing below.

## Glance-layer rule

The matrix and the one-line definitions above are the whole glance layer: they alone answer
"what governs class X". Every deeper question routes to a named leaf — depth is never
answered from this document:

| Deeper question | Leaf |
|---|---|
| What each level means, which substrate classes satisfy it, what happens when none does | [isolation-ladder](guardrails/isolation-ladder.md) |
| What exactly is in each class, and how a promotable cell promotes or demotes | [work-classes](guardrails/work-classes.md) |
| Which verification layers exist and which block, per class | [security-review](guardrails/security-review.md) |
| Which signals may enter the queue autonomously, and under what caps | [admission-policy](guardrails/admission-policy.md) |

## Permission posture

Permission posture is not a matrix column: `L1` is the attended ergonomics tier where
per-action prompts remain the control; at `L2` and above the whole-process boundary is the
control, replacing per-action prompts. The [isolation-ladder](guardrails/isolation-ladder.md)
leaf carries this note in context.

## Escalation

Six escalation event classes:

| Event class | Fires when |
|---|---|
| `gate-failure` | a blocking verification gate fails |
| `verification-divergence` | a verification outcome diverges from the expected or claimed result |
| `admission-rejection` | the admission seam rejects a signal as an audited rejection |
| `demotion` | contrary evidence automatically demotes a promoted cell |
| `structural-plan-approval` | a `C4` item requires upfront plan approval before execution |
| `untrusted-provenance` | always, for every `C5` item |

**Routing obligation.** Every event class has an org-bound route in the security binding —
escalation routes are a security-sensitive axis, so they bind on the governance surface, and
an absent or invalid binding fail-closes per the binding contract.

**Payload.** The work-item reference plus the trace link: every escalation carries the item
it concerns and the trace context joining it into the one causal tree, so the evidence behind
the escalation is queryable from the event.

**Mechanism.** The governed queue itself: an escalation lands as a human-gated work item on
the one queue, with an optional channel notification delivered through the trigger contract's
closed-loop acknowledgment symmetry ([trigger-dispatch](trigger-dispatch.md)).

**The one-channel invariant.** No second escalation channel exists. It is this contract's
own — distinct from, and narrower than, the claim and dispatch paths, which the
[one-entrypoint invariant](trigger-dispatch.md#dispatch) states canonically and which binds
here unchanged.

Interactive escalation UX is deferred; its trigger is the runner design pack.
