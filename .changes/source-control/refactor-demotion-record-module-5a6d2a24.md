---
bump: patch
---

### Changed

- babysit-prs: `babysit_merge_policy.py` owns the post-merge record line (`record_marker`, `parse_record_marker`, `red_main_record`, `liftable_record`), and `babysit_postmerge.py` and `babysit_lift.py` call it. Its grammar and `failing_checks` run the shared vectors in `.github/scripts/post-merge-demotion-alert/demotion-record.vectors.json`, as babysit-loop's `publish-promotion-evidence.mjs` marker does. No behavior changes.
