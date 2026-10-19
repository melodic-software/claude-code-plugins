---
bump: patch
---

### Fixed

- A red full run that pr-merge.yml dispatched now gets its one re-run without a person. The
  `post-merge-dispatch` job, which already holds `actions: write` under `GITHUB_TOKEN`, starts
  `rerun-failed-jobs` on attempt 1 of a red lane-dispatched run the post-merge check reports
  (`laneDispatched` in its `reruns`), one run per job. Once attempt 2 exists it uploads
  `pr-merge-rerun-<run id>-attempt-2`, which the post-merge check needs before it counts that
  attempt. Before this, such a run waited for a re-run the lanes App cannot start, every candidate
  was refused with exit 5, and no demotion record existed for a human to close until a person
  re-ran it. The lanes App gets no new permission. The re-run step runs only when the check
  could judge (exit 0, 1 or 5), after the full-run dispatch, and a failure in either leaves the
  other to run. Once the re-run starts, the step retries reading its attempt for about three
  minutes, and fails with an error rather than finishing quietly when it cannot confirm attempt 2.
