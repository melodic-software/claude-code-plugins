# Issue triage sweep

Normative leaf of the [routine catalog](../routines.md): the `issue-triage-sweep` v1 class
definition — a standing sweep that classifies, routes, and field-annotates untriaged tracker
items.

## Purpose

Untriaged intake is the toil addressed: new tracker items sit unclassified — no component, no
type, no routing — until a human finds the time, and the queue rots while they wait. The
sweep does the recurring semantic pass (classify, route, suggest fields, flag ambiguity) so
human attention lands only where judgment beyond the sweep's is needed.

## Trigger and cadence

Trigger-taxonomy slot: **schedule**. The routine enters work as a `temporal`-class signal
through the [trigger-dispatch contract](../trigger-dispatch.md)'s temporal adapter — a
scheduled trigger behind the governed queue, never a private execution or merge path.
Suggested cadence default: **daily** — an org-bindable value set in the org's routine
binding, never contract-fixed. No vendor scheduling surface is named here; guided setup
researches scheduling surfaces live.

## Access scope

Repo-scoped, including CI and the tracker: the sweep reads the tracker's untriaged items and
writes only through the governed queue and tracker. No production, product, org, or
external-web access — the connector-prerequisite branch of the mapping rules never applies.

## Output contract

- **Work-item updates** — classification, routing, and field annotations on existing tracker
  items (component, type, and priority suggestions), written through the governed
  queue/tracker.
- **Advisory report** — one run report: what was triaged, what stayed ambiguous, what needs
  a human.
- **No direct change** — nothing lands in the repository.

## Derived guardrail row

The row is derived through the catalog-to-matrix mapping rules in the
[routine catalog](../routines.md) — never hand-assigned:

1. **Judgment axis.** Classifying and routing tracker items is semantic judgment no rule
   engine resolves — agent-judgment (`AGT`), which is what makes the class a routine at all
   (deterministic work needs no agent session).
2. **Output axis.** Work-item updates plus a report are governed-queue and tracker writes
   with no repository mutation: the `AGT` + report rule and the `AGT` + work-item rule both
   derive `C1`, and the [work-classes leaf](../guardrails/work-classes.md) scopes queue and
   tracker writes as permitted `C1` output.
3. **Higher-risk axes.** No direct-change rule matches (nothing lands in the repository), so
   neither the mechanically-checkable branch (`C2`/`C3`) nor the structural axis (`C4`)
   fires; the access scope is repo/tracker, not the external-watch access class the
   provenance axis (`C5`) keys on. Composition to the highest matched class leaves `C1`.
4. **Access axis → prerequisite.** Repo scope sets the `L2` unattended floor as the dispatch
   prerequisite — and `C1`'s matrix row keeps that floor because the exfiltration surface
   remains even for read-only work.

Derived row: `C1` in the [guardrail matrix](../guardrails.md).

## Prerequisites

Per-identity needs under
[routine prerequisite resolution](../prerequisite-resolution.md). Axes derive through the
catalog mapping rules; the isolation floor and `executor_class` merge cap are cited from the
guardrail slice, never re-derived. Resolution verdicts use `supported` | `conditional` |
`unsupported` | `unknown`.

Single-posture identity: `issue-triage-sweep` (bare class token).

| Axis | Value |
|---|---|
| Access class | `repo` |
| Isolation floor | `L2` — cited from the [matrix](../guardrails.md#the-matrix) `C1` row and the [unattended floor](../guardrails/isolation-ladder.md#unattended-floor) |
| Connector entitlements | none — `repo` access; the connector branch of [Access to prerequisites](../routines.md#access-to-prerequisites) does not apply |
| Connector entitlement rung | n/a (no connector). For `prod` / `product` / `org` / `ext`, entitlement binds at the [Org binding layer](../binding-seam.md#resolution-ladder) |
| `executor_class` merge cap | cited from [executor surface classes](../trigger-dispatch.md#executor-surface-classes) — security-binding `executor_class`; `vendor-hosted` caps every class at human-gated merge; never repo-derivable. Merge policy for this identity is n/a (`C1`) |
| Repo needs | tracker binding via the work-item tracker seam (`.work-item-tracker.json` + adapter `capabilities.json`); absence is `unknown` per the composition fallback |

## Admission and escalation

Admission disposition, caps, and fail-closed behavior are imported by citation from the
[admission policy](../guardrails/admission-policy.md) — the shipped-defaults row for the
derived class governs, and nothing here restates it. Escalation events and routing are the
derived row's escalation column in the [guardrail matrix](../guardrails.md), org-bound per
its routing obligation.

## Precedent

The proven manual pattern is the recurring human triage sweep over untriaged intake, as
documented in mature projects' triage guides. Precedents from the routine-catalog research
(row 10): narrow ML triage-classifier suites — whose key finding is that "triage" decomposes
into many per-field classification judgments, not one job — plus tracker-native hosted
triage assistants and coding-agent vendors' showcased backlog-maintenance routines.
