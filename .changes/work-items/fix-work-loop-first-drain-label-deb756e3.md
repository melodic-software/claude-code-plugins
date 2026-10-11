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

### Fixed

- close review gaps in the first-drain gate and upsert identity

  first-drain-ratified.sh now decides on the last labeled or unlabeled
  event, rejects an application made through a GitHub App, and rejects
  dot-segment --repo values (as does the upsert). A proposal is raised only
  on exit 1, never on a failed read. Tests cover resolution order and
  underscore-login adoption; the docs state the --app-slug requirement under
  App tokens and the shared-token limit.
