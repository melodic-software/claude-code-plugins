---
bump: minor
---

### Added

- bound the age of the promotion evidence a re-earn after a demotion is read from

  A new setting, `promotion_evidence_max_age_hours`, is read from managed or
  user settings. Under `--window-start`, where every cell that resolves
  promoted was re-ratified after a demotion record, the resolver now reads
  the events file's `evidence.meta.json` sidecar. It fails closed, so a
  demoted cell stays demoted, when the bound is unset or malformed, when the
  sidecar is missing, lane-writable or holds another `sha256`, or when its
  `generated_at` is older than the bound. The stale reason names the file,
  its `generated_at` and the bound. Before this, a publisher that stopped
  running left a re-earned cell promoted with no newer contrary event able
  to reach it. The merge gate also refuses a lane-writable settings file
  that holds the bound.
