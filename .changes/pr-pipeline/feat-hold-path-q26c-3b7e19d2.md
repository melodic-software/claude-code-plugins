---
bump: minor
---

### Changed

- The pr-merge hold-path floor now gives each glob a class (owner decision Q26 option B). `trust` (check-trusted-trigger, check-kill-switch, request-lane-token, CODEOWNERS, .gitmodules) and `gate` (every pr-merge script, the pr-merge and ci-status workflows, `babysit_merge*.py`, `babysit_risk.py` and `babysit_review_evidence.py` (they compute the review's clear condition), the rate guard, resolve-config and the pipeline config) still hold for a person. `enforcement` (the other modules the floored scripts import and the Python that decides the holds) no longer needs a person: the merge gate holds such a path as `review-path:<glob>` until the claude-security-review evidence binds to the head with no open finding, then arms it. ci-status leaves those paths to the gate. One classed list on each side, `HOLD_PATH_CLASSES` (`.github/scripts/pr-merge/merge-holds.mjs`) and `babysit_risk.FLOOR_CLASSES`, pinned equal by `test_merge_holds_sync.py`.
- The rest of `.github/scripts/pr-merge/` (gate-check, rotation, who, lane-records and the other scripts pr-merge.yml runs) joins the floor as `gate`, and both review callers' `hold-paths` and ci-status's exempt-author `hold_patterns` name them.
