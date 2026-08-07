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
current dependency may WAKE the routine's own ratified emitting surface ahead of cadence,
and the resulting run is always a `temporal`-class signal under the routine's protected
identity and run-link namespace, identical to a schedule-tick run (the
[catalog](../routines.md)'s event-riding rule — the run never enters through an event
adapter). Both the cadence and the event-riding wiring are org-bindable values; nothing
here fixes a scheduling surface.

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
   version availability — is deterministic, so it runs with no agent session and zero
   agent tokens and is NOT the routine. The judgment portion — breakage assessment and wave
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

Each posture is a distinct protected routine identity: `dependency-update-wave/mechanical`
(manifest bump + CI verdict, `C2`) and `dependency-update-wave/changelog-informed`
(judgment reasons over attacker-writable upstream prose, `C5`). An org's security binding
keys admission classification by these posture-qualified identities per the
[catalog](../routines.md)'s binding rules — the bare class token is not bindable for a
multi-posture class; the posture the org enables picks the identity it binds.

## Admission and escalation

Admission disposition and fan-out caps for the derived class come from the
[admission policy](../guardrails/admission-policy.md), evaluated over the stamped
`signal.work_class`; escalation follows the [guardrail matrix](../guardrails.md)'s
escalation column for the derived row. This leaf adds no routine-specific admission or
escalation rules.

## Precedent

The proven manual pattern: recurring hand-run dependency sweeps batched into review
waves. Productized precedent makes this class THE guardrail-matrix archetype: scheduled
dependency-update bots with test-gated, policy-controlled automerge matrices. Precedent
record: routine-catalog research, row 16.
