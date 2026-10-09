---
bump: minor
---

### Added

- **The babysit merge gate re-runs an AI review that hit the usage limit.** A `--merge`
  run held on a failed `claude-review-status` or security-review check re-runs that
  check's workflow run when its check run carries a `class=rate-limit` annotation, five
  hours after the failure, on the pinned live head, and only on the run's first attempt,
  and only when the job its `details_url` names emitted that check.
  Every other failure class is left alone, a check-only run never re-runs, and auto-merge
  still arms only on SUCCESS. The JSON reports each decision under `aiReviewReruns`.

### Changed

- **`/source-control:pull-request ready` adds a fresh-context code review.** Before the flip,
  `/code-review` (or the review plugin's reviewer agents) runs over the pull request's diff
  in a subagent that gets the diff and the acceptance criteria, not the author's reasoning,
  beside the security review, which now runs the same way. Findings are fixed or recorded.
