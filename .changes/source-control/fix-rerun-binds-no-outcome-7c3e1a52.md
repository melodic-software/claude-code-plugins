---
bump: patch
---

### Fixed

- `/source-control:babysit-prs` binds a review lane's second attempt after the first attempt's lane job ended before reporting an outcome (the `NO_OUTCOME` class), when the lane posted nothing on the head between the two attempts' starts and the first attempt left no completion record. Pull requests caught in the 2026-11-01 review-lane outage were held as `rerun-not-allowed` even after a clean re-run. The merge gate does not start this re-run: a defect in the lane fails every run until its fix ships, and a re-run before then would spend the one allowed attempt.
