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

## Admission and escalation

Admission disposition and fan-out caps for the derived class come from the
[admission policy](../guardrails/admission-policy.md), evaluated over the stamped
`signal.work_class`; escalation follows the [guardrail matrix](../guardrails.md)'s
escalation column for the derived row. This leaf adds no routine-specific admission or
escalation rules.

## Precedent

The proven manual pattern: periodic hand-run CI reviews after incidents or visible
slowdowns. Productized precedent: scheduled pipeline doctoring, coaching, and cost
tracking (marked examples: gh-aw CI Doctor, CI Coach, Cost Tracker). Precedent record:
routine-catalog research, row 31.
