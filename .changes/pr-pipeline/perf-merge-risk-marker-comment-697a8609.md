---
bump: minor
---

### Changed

- Each arm records the report-only `Merge-Risk:` line in a lanes App comment whose first line is
  `<!-- merge-risk-line head=<sha> -->`, no longer as the pull request body's last line, so an arm
  starts no `pull_request: edited` pr-require-checks run, no downstream pr-verify,
  pr-verify-capture, pr-rate-merge-risk or pr-review-main run, and no queue wait for them. The arm
  posts the comment once per head, edits it when that head's line changes, and writes nothing when
  it already holds the line, from the comments it already read. The rating values and the
  `pr-merge-risk` artifact are unchanged; the squash commit no longer carries the line, and a
  revert study finds the rating through the revert's `(#N)` in that pull request's comment.
