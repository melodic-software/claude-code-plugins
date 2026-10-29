---
bump: minor
---

### Added

- lane-arm the merge gate's own code on a clean main-run review

  With `merge.lane-arm-gate` on, the merge gate's risk score drops the
  `high-path:` hold on `babysit_risk.py` and the pr-merge scripts
  (`LANE_ARMED_FLOOR`) when both review lanes are bound to a main-run review
  of the head (`LaneEvidence.main_run`) with no open finding and the pull
  request has no unresolved review thread (`RiskInput.open_threads`). Those
  paths are lane sources, so only a main-run review binds them. The gate
  records what pr-merge's attestation needs as `laneArmed`
  (`babysit_risk.lane_arm_record`), with the first failed condition. Every
  other floor path, a configured denied path and any unread input keep the
  person hold.
