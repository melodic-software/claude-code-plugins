---
bump: patch
---

### Fixed

- A write lane `pull_request` run on a PR that changes a workflow file the token broker compares no
  longer fails red. When the broker refuses the mint as `workflow-modified` and GitHub's compare of
  the default branch with the gated head lists the named file, the run job ends green with no token,
  its summary names the reason and file, and the check is neutral with the new skip reason
  `workflow-modified` ([pr-run-activity.md](pr-run-activity.md#a-workflow-file-the-pr-changes)).
  Every other denial, and a refusal of a file the PR does not change, stays red. `version` stays 2.
