---
bump: patch
---

### Fixed

- bind lane comments to their producing run

  Every workflow's job token posts as github-actions[bot], so the
  `claude-lane: <lane>` footer alone does not show a comment came from a
  review lane. Readers now accept a github-actions[bot] lane comment only
  when the run its binding line names (`<!-- claude-lane-run id=<run>
  sha=<head> -->`, written by ci-workflows' pr-review-cli) is that lane's
  caller workflow, ran on that head, and lists the comment's kind, id and
  body digest in one of its `claude-lane-comments-<lane>-<attempt>`
  artifacts. Every attempt's record counts; a run whose record expired
  proves its comments by time. A comment that fails reads as one with no
  footer; one that passes is read without its binding line, so severity
  and footer parsing is unchanged. Comments with no binding keep counting
  while LEGACY_CUTOFF is unset; a later change sets it once the lanes
  write bindings.

  - .github/scripts/lib/lane-binding.mjs, its fixtures and test (copies in
    the review and work-items plugins), and babysit_lane_binding.py.
  - pr-unblock: address-feedback, feedback-dispatch, publish-feedback,
    resolve-threads, lane-hold, gate-recheck, dispatch and fix-ci-context
    read comments and timelines through withLaneBinding.
  - pr-merge: clear-escalations (thread roots, hold timelines, and the
    ci-status filterLaneHolds entry), enable-auto-merge's lift check.
  - ci-status: hold comments pass through filterLaneHolds from the base.
  - babysit merge gate, review prior-findings, morning-brief
    review-precision.
  - ARTIFACT_READ_TOKEN and `actions: read` where a job reads the records;
    the library and Python module join the hold floor as enforcement.
