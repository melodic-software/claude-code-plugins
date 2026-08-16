# CI health review

Normative leaf of the [routine catalog](../routines.md): the v1 `ci-health-review` class
definition. Vocabulary is contract-owned; every concrete value (cadence, CI platform,
cost signals) is an org-binding outcome.

## Purpose

Toil addressed: CI degrades silently — pipelines slow down, flake rates creep, caches go
stale, spend drifts — and nobody reviews the pipeline itself until it hurts. The review
periodically assesses pipeline health (duration, reliability, cost, configuration
hygiene) and turns the findings into queued, actionable work.

## Trigger and cadence

Trigger-taxonomy slot: schedule, entering the queue through the
[trigger contract](../trigger-dispatch.md)'s `temporal` surface class. Suggested cadence
default: weekly — an org-bindable value.

## Access scope

Repo — repository, CI, and tracker surfaces only. Per the catalog mapping rules' access
axis, repo scope sets the `L2` unattended floor as the class prerequisite
([guardrail contract](../guardrails.md)).

## Output contract

Advisory report — the period's pipeline-health assessment — plus work items filed into
the governed queue for each finding warranting action. OPTIONALLY, a gated change: a
proposed fix to CI workflow/config, entering only through the guardrail matrix's merge
policy for the derived row of that portion. The optional change is never a second merge
path and never lands unreviewed.

## Derived guardrail row

The row is derived through the catalog's mapping rules, never hand-assigned:

1. **Advisory portion.** Agent judgment producing a report plus work items, no
   repository mutation → `C1`, with the `L2` unattended floor.
2. **Direct-change portion (optional).** A change to CI workflow/config touches a
   structural/config surface, so the structural-blast-radius axis derives `C4` —
   deterministic + AI + human review mandatory, human merge always — regardless of how
   small the edit looks.
3. **Composition rule.** Where one derivation matches multiple rules, it composes to the
   highest-risk class (`C5` > `C4` > `C3` > `C2` > `C1`). A run emitting only the report
   and work items stays `C1`; any run producing the gated CI-config change carries the
   composed `C4` row for that change — the lower advisory row never dilutes it.

Derived row: `C1` for the advisory portion; `C4` for the optional CI-config change.

Each posture is a distinct protected routine identity: `ci-health-review/advisory`
(report + work items, `C1`) and `ci-health-review/ci-config-change` (the optional gated
CI-config path, `C4`). An org's security binding keys admission classification by these
posture-qualified identities per the [catalog](../routines.md)'s binding rules — the bare
class token is not bindable for a multi-posture class; the posture the org enables picks
the identity it binds.

## Prerequisites

Per-identity needs under
[routine prerequisite resolution](../prerequisite-resolution.md). Axes derive through the
catalog mapping rules; the isolation floor and `executor_class` merge cap are cited from the
guardrail slice, never re-derived. Resolution verdicts use `supported` | `conditional` |
`unsupported` | `unknown`. The two postures diverge on merge-path needs — different
prerequisite sets for the same class.

### `ci-health-review/advisory`

| Axis | Value |
|---|---|
| Access class | `repo` |
| Isolation floor | `L2` — cited from the [matrix](../guardrails.md#the-matrix) `C1` row and the [unattended floor](../guardrails/isolation-ladder.md#unattended-floor) |
| Connector entitlements | none — `repo` access; the connector branch of [Access to prerequisites](../routines.md#access-to-prerequisites) does not apply |
| Connector entitlement rung | n/a (no connector). For `prod` / `product` / `org` / `ext`, entitlement binds at the [Org binding layer](../binding-seam.md#resolution-ladder) |
| `executor_class` merge cap | cited from [executor surface classes](../trigger-dispatch.md#executor-surface-classes) — security-binding `executor_class`; `vendor-hosted` caps every class at human-gated merge; never repo-derivable. Merge policy for this identity is n/a (`C1`) |
| Repo needs | CI-config presence (ownerless repo-file probe owned by the resolution contract); tracker binding when filing work items through the work-item tracker seam |

### `ci-health-review/ci-config-change`

| Axis | Value |
|---|---|
| Access class | `repo` |
| Isolation floor | `L2` — cited from the [matrix](../guardrails.md#the-matrix) `C4` row and the [unattended floor](../guardrails/isolation-ladder.md#unattended-floor) |
| Connector entitlements | none — `repo` access; the connector branch of [Access to prerequisites](../routines.md#access-to-prerequisites) does not apply |
| Connector entitlement rung | n/a (no connector). For `prod` / `product` / `org` / `ext`, entitlement binds at the [Org binding layer](../binding-seam.md#resolution-ladder) |
| `executor_class` merge cap | cited from [executor surface classes](../trigger-dispatch.md#executor-surface-classes) — security-binding `executor_class`; `vendor-hosted` caps every class at human-gated merge; never repo-derivable. `C4` is human merge always; the cap still binds |
| Repo needs | everything `advisory` requires, plus a merge-bearing path through the matrix for the gated CI-config change — the identity is not eligible where the bound surface cannot carry a merge-policy disposition |

## Admission and escalation

Admission disposition and fan-out caps for the derived class come from the
[admission policy](../guardrails/admission-policy.md), evaluated over the stamped
`signal.work_class`; escalation follows the [guardrail matrix](../guardrails.md)'s
escalation column for the derived row. This leaf adds no routine-specific admission or
escalation rules.

## Precedent

The proven manual pattern: periodic hand-run CI reviews after incidents or visible
slowdowns. Productized precedent: hosted agentic pipeline-doctor, coach, and cost-tracker
workflow samples running on schedule. Precedent record: routine-catalog research, row 31.
