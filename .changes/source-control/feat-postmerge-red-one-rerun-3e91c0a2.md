---
bump: patch
---

### Fixed

- `babysit_postmerge.py --lane-merges-only` marks a red attempt 1 of a full run the pr-merge lane
  dispatched for the lane's one re-run even when no judged lane merge covers it, when the run is
  under 90 minutes old and a newly failing check demotes by the affected-set rule. Before, such a
  run got no re-run and post-merge-demotion-alert.yml demoted on attempt 1 alone. The probe files
  no quarantine issue, and a failed read is a `lane-rerun-unreadable` warning, not an unreadable
  verdict.
