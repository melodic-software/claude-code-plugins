# Backlog readiness check

Normative leaf of the [routine catalog](../routines.md): the `backlog-readiness-check` v1
class definition — a standing pass that annotates backlog items with what refinement will
need before the meeting discovers it.

## Purpose

Refinement-time discovery is the toil addressed: backlog sessions burn shared meeting time
finding out an item is not ready — acceptance criteria missing, fields absent, scope
unclear. The check does the recurring pre-refinement pass and annotates each item with what
is missing, so refinement starts from ready-or-annotated items instead of live archaeology.

## Trigger and cadence

Trigger-taxonomy slot: **schedule**. The routine enters work as a `temporal`-class signal
through the [trigger-dispatch contract](../trigger-dispatch.md)'s temporal adapter — a
scheduled trigger behind the governed queue, never a private execution or merge path.
Suggested cadence default: **daily** — an org-bindable value set in the org's routine
binding, never contract-fixed. No vendor scheduling surface is named here; guided setup
researches scheduling surfaces live.

## Access scope

Repo-scoped, including CI and the tracker: the check reads the backlog's items and writes
only through the governed queue and tracker. No production, product, org, or external-web
access — the connector-prerequisite branch of the mapping rules never applies.

## Output contract

- **Work-item annotations** — readiness notes on backlog items: missing acceptance
  criteria, absent fields, unclear scope, unstated dependencies — annotations only, never
  silent edits of an item's intent.
- **Advisory report** — one run report: readiness state of the swept backlog slice and the
  items needing author attention.
- **No direct change** — nothing lands in the repository.

## Derived guardrail row

The row is derived through the catalog-to-matrix mapping rules in the
[routine catalog](../routines.md) — never hand-assigned:

1. **Judgment axis.** Judging whether an item is actionable — whether its acceptance
   criteria, scope, and fields would let work start — is semantic judgment no rule engine
   resolves — agent-judgment (`AGT`), which is what makes the class a routine at all
   (deterministic work needs no agent session).
2. **Output axis.** Work-item annotations plus a report are governed-queue and tracker
   writes with no repository mutation: the `AGT` + report rule and the `AGT` + work-item
   rule both derive `C1`, and the [work-classes leaf](../guardrails/work-classes.md) scopes
   queue and tracker writes as permitted `C1` output.
3. **Higher-risk axes.** No direct-change rule matches (nothing lands in the repository), so
   neither the mechanically-checkable branch (`C2`/`C3`) nor the structural axis (`C4`)
   fires; the access scope is repo/tracker, not the external-watch access class the
   provenance axis (`C5`) keys on. Composition to the highest matched class leaves `C1`.
4. **Access axis → prerequisite.** Repo scope sets the `L2` unattended floor as the dispatch
   prerequisite — and `C1`'s matrix row keeps that floor because the exfiltration surface
   remains even for read-only work.

Derived row: `C1` in the [guardrail matrix](../guardrails.md).

## Admission and escalation

Admission disposition, caps, and fail-closed behavior are imported by citation from the
[admission policy](../guardrails/admission-policy.md) — the shipped-defaults row for the
derived class governs, and nothing here restates it. Escalation events and routing are the
derived row's escalation column in the [guardrail matrix](../guardrails.md), org-bound per
its routing obligation.

## Precedent

The proven manual pattern is the pre-refinement grooming pass a lead or product owner runs
before the session so the meeting refines instead of investigates. Precedents from the
routine-catalog research (row 13): tracker-native readiness checkers that flag missing
fields and acceptance criteria, and tracker triage-intelligence features that suggest item
properties.
