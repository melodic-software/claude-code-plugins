---
bump: patch
---

### Changed

- The convention names the renamed pull request jobs by their verb-first ids: pr-merge's
  `dispatch-post-merge-runs`, `report-unarmed-status` and `report-gate-checks`; pr-refine's
  `check-dispatcher-current`, `select-passes` and `upload-key-credit-markers`; pr-unblock's
  `check-conflict-scan-refusal` and `check-adjudicator-key-credit`; the hosted reviews'
  `wait-for-refine`; pr-review-main's `collect-trusted-text`, `collect-subscription-handoffs` and
  `report-review-counts`; and the read runner's `check-issue-fields` and `generate-reuse-summary`.
  Each job's display name is its id in Title Case. Check-run names, statuses, markers and artifact
  names are unchanged.
