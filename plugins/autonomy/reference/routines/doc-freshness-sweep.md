# Doc-freshness sweep

Normative leaf of the [routine catalog](../routines.md): the `doc-freshness-sweep` v1 class
definition — a standing sweep that judges whether docs still describe the code they claim
to, reporting drift and optionally preparing gated docs changes.

## Purpose

Silent documentation drift is the toil addressed: docs fall out of step with the code they
describe, and the staleness is discovered by the next misled reader rather than by any
process. The sweep does the recurring semantic comparison — does this doc still match its
subject? — and surfaces the drift, so doc accuracy stops depending on someone happening to
reread the right page.

## Trigger and cadence

Trigger-taxonomy slot: **schedule**. The routine enters work as a `temporal`-class signal
through the [trigger-dispatch contract](../trigger-dispatch.md)'s temporal adapter — a
scheduled trigger behind the governed queue, never a private execution or merge path.
Suggested cadence default: **weekly** — an org-bindable value set in the org's routine
binding, never contract-fixed. No vendor scheduling surface is named here; guided setup
researches scheduling surfaces live.

## Access scope

Repo-scoped, including CI and the tracker: the sweep reads the repository's docs and the
code they describe, and writes through the governed queue and tracker — plus, only where the
org enables the gated docs-change path below, through the matrix's merge policy. No
production, product, org, or external-web access — the connector-prerequisite branch of the
mapping rules never applies.

## Output contract

- **Advisory report** — one run report: docs whose subjects changed since they did,
  suspected-stale passages, and drift too ambiguous to judge.
- **Work items** — filed through the governed queue for drift whose correction needs
  authorial judgment.
- **Optional gated docs-change path** — an org MAY enable a direct docs-change path
  (a prepared docs change entering through the matrix's merge policy). It is off unless the
  org's routine binding enables it, and enabling it changes the derived posture below.

## Derived guardrail row

The row is derived through the catalog-to-matrix mapping rules in the
[routine catalog](../routines.md) — never hand-assigned, and derived per portion because the
class has two output shapes:

1. **Judgment axis.** Whether a doc still truthfully describes its subject is semantic
   judgment no rule engine resolves — agent-judgment (`AGT`), which is what makes the class
   a routine at all (deterministic work stays plain cron; a bare last-touched-date reminder
   is the deterministic neighbor, not this class).
2. **Advisory portion.** The report plus work items are governed-queue and tracker writes
   with no repository mutation: the `AGT` + report rule and the `AGT` + work-item rule both
   derive `C1`, and the [work-classes leaf](../guardrails/work-classes.md) scopes queue and
   tracker writes as permitted `C1` output.
3. **Gated docs-change portion.** The optional path is `AGT` + direct change, so the
   mechanically-checkable branch decides between `C2` and `C3` — and doc accuracy is NOT
   mechanically checkable: no deterministic gate can decide whether prose now tells the
   truth about the code, because the truth being checked is semantic. The portion derives
   `C3`, not `C2`.
4. **Higher-risk axes.** Docs are not the structural/config surfaces the `C4` axis names,
   and the access scope is repo, not the external-watch access class the provenance axis
   (`C5`) keys on — neither fires.
5. **Composition.** When multiple portions match, the highest-risk class governs the posture
   actually enabled: advisory-only deployment runs as `C1`; enabling the docs-change path
   composes to `C3`, and the whole enabled posture is governed by the `C3` row (its
   verification stack and human merge included).
6. **Access axis → prerequisite.** Repo scope sets the `L2` unattended floor as the dispatch
   prerequisite; both `C1` and `C3` matrix rows keep the floor at `L2`.

Derived row: `C1` advisory-only, `C3` with the docs-change path enabled — both in the
[guardrail matrix](../guardrails.md).

Each posture binds a distinct protected routine identity per the
[routine catalog](../routines.md)'s posture-identity rule: `doc-freshness-sweep/advisory`
(report + work items, `C1`) and `doc-freshness-sweep/docs-change` (the gated docs-change
path, `C3`). An org's security binding keys admission classification by these
posture-qualified identities — the bare class token is not bindable for a multi-posture
class.

## Admission and escalation

Admission disposition, caps, and fail-closed behavior are imported by citation from the
[admission policy](../guardrails/admission-policy.md) — the shipped-defaults row for the
derived class of the enabled posture governs, and nothing here restates it. Escalation
events and routing are the derived row's escalation column in the
[guardrail matrix](../guardrails.md), org-bound per its routing obligation.

## Precedent

The proven manual pattern is the periodic docs review pass — someone rereads the docs their
team owns against the current code and fixes or files what drifted. Precedents from the
routine-catalog research (row 26): doc-code coupling tools that verify freshness per
change, doc freshness-date conventions with automated staleness reminders, hosted
agentic-workflow sample packs' scheduled documentation updaters, and coding-agent vendors'
showcased docs-drift routines.
