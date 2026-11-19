---
bump: patch
---

### Fixed

- `babysit_verify_evidence.py settle --probe-unmoved` refuses a last report that lists reruns as `reruns-unmoved` when nothing else it read has moved, so a PR-scoped `pr-merge.yml` wake skips the fresh post-merge check.
