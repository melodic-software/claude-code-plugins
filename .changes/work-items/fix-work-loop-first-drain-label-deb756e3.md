---
bump: patch
---

### Fixed

- end the first-drain period only on a person-applied label

  work-loop's first-drain C3 gate lifted on first_drain_complete, a flag in
  the lane's own telemetry comment, so the lane could widen its own autonomy.
  The gate now lifts only when first-drain-ratified.sh finds the
  `loop-lane: first-drain-ratified` label on the lane's telemetry issue,
  applied by a User actor. A completed drain proposes instead: a
  kind=ratify-first-drain escalation that attend-queue lists as a [ratify]
  row. The reference names which durable-state fields may stay
  lane-writable and why.

  lane-telemetry-upsert.sh now adopts only sentinel comments its write
  identity authored (the gh api user login, or <slug>[bot] via --app-slug,
  matching babysit-loop), checks a create's author, and exits 15 when the
  identity is unresolved.
