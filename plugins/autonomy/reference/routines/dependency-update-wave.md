# Dependency update wave

Normative leaf of the [routine catalog](../routines.md): the v1 `dependency-update-wave`
class definition. Vocabulary is contract-owned; every concrete value (cadence, posture,
surfaces, tooling) is an org-binding outcome.

## Purpose

Toil addressed: manually tracking upstream releases, deciding which updates are safe to
take together, and shepherding the resulting bumps through review. The wave batches
available updates, assesses breakage risk, and lands the batch through the governed merge
policy instead of leaving updates to accumulate until a forced, high-risk catch-up.

## Trigger and cadence

Trigger-taxonomy slot: schedule, entering the queue through the
[trigger contract](../trigger-dispatch.md)'s `temporal` surface class. Suggested cadence
default: weekly, WITH event-riding on advisories — a security-advisory event affecting a
current dependency may fire the wave ahead of cadence rather than waiting for the next
slot. Both the cadence and the event-riding wiring are org-bindable values; nothing here
fixes a scheduling surface.

## Access scope

Repo — repository, CI, and tracker surfaces only. Per the catalog mapping rules' access
axis, repo scope sets the `L2` unattended floor as the class prerequisite
([guardrail contract](../guardrails.md)).

## Output contract

Gated change — update PRs entering through the guardrail matrix's merge policy for the
derived row — plus an advisory report per wave (what was taken, what was held back, and
why). No private merge path exists: the wave's changes land only through the matrix.

## Derived guardrail row

The row is derived through the catalog's mapping rules, never hand-assigned:

1. **Hybrid split.** The class is a hybrid: its detection portion — manifest diff, new
   version availability — is deterministic, so it routes to plain cron with zero agent
   tokens and is NOT the routine. The judgment portion — breakage assessment and wave
   composition — IS the routine and derives through the agent-judgment rules.
2. **Judgment + output axes.** Agent judgment producing a direct change whose truth is
   mechanically checkable — the CI verdict decides whether the wave is good — derives
   `C2`, with the `L2` unattended floor.
3. **Provenance axis — two postures.** Upstream release notes and changelogs are
   attacker-writable external content. A wave posture whose breakage judgment reasons
   over them matches the untrusted-provenance rule, and overlapping matches compose to
   the highest-risk class, so that posture derives `C5` (`L3` floor, human merge always).
   The mechanical-only posture — manifest bump plus CI verdict, no external prose in the
   reasoning loop — keeps the `C2` derivation.

Derived row: `C2` for the mechanical-only posture; `C5` for the release-note-reading
posture. The org binding picks one posture, and the bound posture's row governs.

## Admission and escalation

Admission disposition and fan-out caps for the derived class come from the
[admission policy](../guardrails/admission-policy.md), evaluated over the stamped
`signal.work_class`; escalation follows the [guardrail matrix](../guardrails.md)'s
escalation column for the derived row. This leaf adds no routine-specific admission or
escalation rules.

## Precedent

The proven manual pattern: recurring hand-run dependency sweeps batched into review
waves. Productized precedent makes this class THE guardrail-matrix archetype — dependency
bots with policy-controlled automerge matrices (marked examples: Renovate, Dependabot).
Precedent record: routine-catalog research, row 16.
