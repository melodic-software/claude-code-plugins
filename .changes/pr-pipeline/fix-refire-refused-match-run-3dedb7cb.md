---
bump: patch
---

### Fixed

- Every lane check run `report-check-run` posts now carries `external_id` `<lane>:<activity>:<run id>:<run attempt>`, not only one with a lane record. GitHub returns these check runs with `details_url` set to the check run's own page, so pr-merge's re-fire of a run the broker refused as `workflow-modified` never found the PR, and fix-ci-dispatch never paired a fix-ci check with its run's lane-stopped stop. Both now read the posting run from `external_id`.
