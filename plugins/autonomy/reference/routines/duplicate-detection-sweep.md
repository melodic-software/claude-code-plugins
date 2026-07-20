# Duplicate-detection sweep

Normative leaf of the [routine catalog](../routines.md): the `duplicate-detection-sweep` v1
class definition — a standing sweep that surfaces candidate-duplicate tracker items and links
them.

## Purpose

Unlinked duplicates are the toil addressed: the same defect or request accumulates as
separate tracker items, splitting discussion, votes, and effort across copies until someone
happens to recognize one. The sweep does the recurring semantic comparison across open items
and links candidates, so the human decision is a disposition on a surfaced pair, not a
memory-dependent hunt.

## Trigger and cadence

Trigger-taxonomy slot: **schedule**. The routine enters work as a `temporal`-class signal
through the [trigger-dispatch contract](../trigger-dispatch.md)'s temporal adapter — a
scheduled trigger behind the governed queue, never a private execution or merge path.
Suggested cadence default: **daily** — an org-bindable value set in the org's routine
binding, never contract-fixed. No vendor scheduling surface is named here; guided setup
researches scheduling surfaces live.

## Access scope

Repo-scoped, including CI and the tracker: the sweep reads the tracker's open items and
writes only through the governed queue and tracker. No production, product, org, or
external-web access — the connector-prerequisite branch of the mapping rules never applies.

## Output contract

- **Work-item links** — candidate-duplicate links between tracker items, with the sweep's
  confidence noted; closing or merging a duplicate stays a human disposition.
- **Advisory report** — one run report: link candidates, clusters, and anything too
  ambiguous to link.
- **No direct change** — nothing lands in the repository, and no item is closed by the
  sweep.

## Derived guardrail row

The row is derived through the catalog-to-matrix mapping rules in the
[routine catalog](../routines.md) — never hand-assigned:

1. **Judgment axis.** Judging whether two differently-worded items describe the same thing
   is semantic similarity no rule engine resolves — agent-judgment (`AGT`), which is what
   makes the class a routine at all (deterministic work stays plain cron).
2. **Output axis.** Work-item links plus a report are governed-queue and tracker writes with
   no repository mutation: the `AGT` + report rule and the `AGT` + work-item rule both
   derive `C1`, and the [work-classes leaf](../guardrails/work-classes.md) scopes queue and
   tracker writes as permitted `C1` output.
3. **Higher-risk axes.** No direct-change rule matches (nothing lands in the repository, no
   item is closed), so neither the mechanically-checkable branch (`C2`/`C3`) nor the
   structural axis (`C4`) fires; the access scope is repo/tracker, not the external-watch
   access class the provenance axis (`C5`) keys on. Composition to the highest matched class
   leaves `C1`.
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

The proven manual pattern is the human duplicate hunt: a maintainer recognizes a familiar
report and searches for the original before triaging the copy. Research-catalog precedents
(vendor names as marked examples only): GitHub's inline duplicate detection at issue-compose
time, Linear Triage Intelligence's similar-issue surfacing, and Mozilla bugbug's duplicate
classification.
