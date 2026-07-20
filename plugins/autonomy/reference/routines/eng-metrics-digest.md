# Eng-metrics digest

Normative leaf of the [routine catalog](../routines.md): the v1 `eng-metrics-digest`
class definition. Vocabulary is contract-owned; every concrete value (cadence, metric
set, report destination) is an org-binding outcome.

## Purpose

Toil addressed: assembling the recurring engineering status picture by hand — collecting
activity, review, CI, and delivery signals from repository, CI, and tracker surfaces,
then writing the narrative nobody has time to write. The digest produces that narrative
on cadence, so trends surface without a human doing the collation.

## Trigger and cadence

Trigger-taxonomy slot: schedule, entering the queue through the
[trigger contract](../trigger-dispatch.md)'s `temporal` surface class. Suggested cadence
default: weekly — an org-bindable value.

## Access scope

Repo — repository, CI, and tracker surfaces only. Per the catalog mapping rules' access
axis, repo scope sets the `L2` unattended floor as the class prerequisite
([guardrail contract](../guardrails.md)).

## Output contract

Advisory report only: a narrative digest over the period's repository, CI, and tracker
signals, delivered through the queue's audit trail. No work-item filing obligation and no
repository mutation — anything actionable the digest surfaces routes to other classes or
to humans.

## Derived guardrail row

The row is derived through the catalog's mapping rules, never hand-assigned:

1. **Judgment axis.** The narrative — what mattered, what changed, what trends — is
   agent judgment, so the class is a routine, not plain cron; the underlying counters
   alone would be deterministic, but the digest's value IS the judgment over them.
2. **Output axis.** Advisory report only, no repository mutation → `C1`, with the `L2`
   unattended floor (the read-only class's exfiltration surface remains).

Derived row: `C1`.

## Admission and escalation

Admission disposition and fan-out caps for the derived class come from the
[admission policy](../guardrails/admission-policy.md), evaluated over the stamped
`signal.work_class`; escalation follows the [guardrail matrix](../guardrails.md)'s
escalation column for the derived row. This leaf adds no routine-specific admission or
escalation rules.

## Precedent

The proven manual pattern: a hand-written weekly engineering status update. Productized
precedent: workflow-metadata digest bots and scheduled narrative status reports over
repository and delivery activity. Precedent record: routine-catalog research, row 29.
