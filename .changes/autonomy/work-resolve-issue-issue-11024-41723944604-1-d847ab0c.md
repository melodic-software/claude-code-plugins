---
bump: minor
---

### Changed

- **Escalation routes to the owning lane unless the stop rule applies.** The guardrail escalation
  contract (`reference/guardrails.md#escalation`) adds a "Stops for a person" column and a stop
  rule: `gate-failure`, `verification-divergence` and `demotion` go to the lane that owns the
  follow-up, an `admission-rejection` stays final on the audit trail, and each stops for a person
  only for an intent or vision change, a finding that alters intent or the primary design, or a
  HIGH or CRITICAL security or cost risk. `structural-plan-approval` stops only when the plan
  changes intent or the primary design, and `untrusted-provenance` still always stops. The
  matrix's escalation cells, the unanimity rule (here and in `guardrails/verification-topology.md`)
  and the runner's `gate-failed` outcome (`runner/escalation.md`) no longer send a dissent or
  failed gate to the human gate by default. An item on a lane's route that no lane claims within
  the staleness window re-escalates once to intake, one severity level up, so a stopped lane
  cannot hold it unseen. The binding schema is unchanged (#11024).
