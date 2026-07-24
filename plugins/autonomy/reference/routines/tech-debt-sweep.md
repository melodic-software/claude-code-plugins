# Tech-debt sweep

Normative leaf of the [routine catalog](../routines.md): the v1 `tech-debt-sweep` class
definition. Vocabulary is contract-owned; every concrete value (cadence, hotspot tooling,
recipe tooling) is an org-binding outcome.

## Purpose

Toil addressed: debt is noticed in passing and forgotten — nobody owns the recurring pass
that turns "we should clean this up someday" into concrete, sized, queued work. The sweep
periodically characterizes debt hotspots and files them as work items, so prioritization
happens over an evidence-backed inventory instead of memory and anecdote.

## Trigger and cadence

Trigger-taxonomy slot: schedule, entering the queue through the
[trigger contract](../trigger-dispatch.md)'s `temporal` surface class. Suggested cadence
default: weekly — an org-bindable value.

## Access scope

Repo — repository, CI, and tracker surfaces only. Per the catalog mapping rules' access
axis, repo scope sets the `L2` unattended floor as the class prerequisite
([guardrail contract](../guardrails.md)).

## Output contract

Work items filed into the governed queue: each hotspot as a characterized, sized item
with its evidence. No repository mutation, and no self-disposition — the PRIORITIZATION
of the filed items (what gets fixed, in what order) is human-gated always. Deterministic
recipe-driven remediation is separate cron-scoped work, never this routine's output.

## Derived guardrail row

The row is derived through the catalog's mapping rules, never hand-assigned:

1. **Hybrid split.** The class is a hybrid: deterministic recipe execution —
   codemod-style transformations that need no judgment — runs with no agent session and
   zero agent tokens and is NOT the routine. The judgment portion — hotspot analysis and debt
   characterization — IS the routine.
2. **Judgment + output axes.** Agent judgment filing work items into the governed queue,
   no repository mutation → `C1`, with the `L2` unattended floor.
3. **Human-decision boundary.** The prioritization DECISION is agent-prepares,
   human-decides: its disposition is human-gated always, regardless of the sweep's own
   `C1` derivation — the routine prepares the inventory; it never ranks-and-commits the
   campaign on its own authority.

Derived row: `C1` for the sweep; human-gated disposition for the prioritization decision.

## Admission and escalation

Admission disposition and fan-out caps for the derived class come from the
[admission policy](../guardrails/admission-policy.md), evaluated over the stamped
`signal.work_class`; escalation follows the [guardrail matrix](../guardrails.md)'s
escalation column for the derived row. This leaf adds no routine-specific admission or
escalation rules.

## Precedent

The proven manual pattern: recurring hand-run debt review sessions producing a backlog of
cleanup tickets. Productized precedent: hotspot-ROI code-health platforms prioritizing by
change frequency, deterministic refactoring-recipe engines running remediation campaigns,
and dedicated org-wide fix-it cadences. Precedent record: routine-catalog research,
row 24.
