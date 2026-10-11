---
bump: patch
---

### Fixed

- end the first-drain period only on a person-applied label

  work-loop's first-drain C3 gate lifted on first_drain_complete, a flag in
  the lane's own telemetry comment, so the lane could widen its own autonomy.
  The gate now lifts only when first-drain-ratified.sh finds the
  `loop-lane: first-drain-ratified` label on the lane's telemetry issue,
  where its last labeled or unlabeled event is an application by a User
  actor not acting through a GitHub App. A completed drain proposes instead:
  a kind=ratify-first-drain escalation on the telemetry issue, which
  attend-queue lists as a [ratify] row despite its lane-infrastructure
  exclusion. The reference names which durable-state fields may stay
  lane-writable and why.

- adopt only the write identity's telemetry comments

  lane-telemetry-upsert.sh now adopts only sentinel comments its write
  identity authored (the gh api user login, or <slug>[bot] via --app-slug,
  matching babysit-loop), checks a create's author, rejects dot-segment
  --repo values, and exits 15 when the identity is unresolved.
