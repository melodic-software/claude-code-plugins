---
bump: minor
---

### Added

- A `triage_cluster` setting in `docs/conventions/work-items.yaml` (repository layer only) holds the
  signature-cluster defaults `/work-items:triage` uses: `signatures` (which shared signatures form a
  cluster: `error`, `symptom`, `commit`; default all three), `min_members` (default 2) and `parent`
  (`oldest-reproduced`, the default, or `oldest`). Triage reports the values and their layer when a
  cluster forms. The defaults are provisional until tuned on the first 20 clusters.
