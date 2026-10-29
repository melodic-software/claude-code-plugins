---
bump: minor
---

### Added

- lane-arm gate paths on a clean main-run review

  With `merge.lane-arm-gate` on, the merge gate's risk score drops the
  `high-path:` hold on a lane-armed `gate` floor path when both review lanes
  are bound to a main-run review of the head (`LaneEvidence.main_run`) with no
  open finding and the pull request has no unresolved review thread
  (`RiskInput.open_threads`, read only when it could lane-arm a path). A
  `trust` path, a person-held path, a configured denied path and any unread
  input keep the person hold. No path is lane-armed yet: every `gate` row is
  person-held. `plugins/review/skills/**` and `plugins/review/reference/**`
  are new `gate` floor paths.
