---
bump: patch
---

### Fixed

- `babysit_postmerge.py` counts a `github-actions[bot]` attempt 2 of a full run the pr-merge lane
  dispatched when pr-merge.yml's own `pr-merge-rerun-<run id>-attempt-2` record backs it: an
  artifact uploaded by a pr-merge.yml run of this repository's own copy of the file on the judged
  branch. Green on that attempt is a flake; red is a failure. Without the
  record, with a record for another run or attempt, or when a person started attempt 2, it still
  reads red, except that a bot attempt 2 of a lane-dispatched run still in progress waits for its
  record instead. A failed read of the record makes the verdict unreadable (exit 3).
- Its report marks each red full run awaiting its re-run with `laneDispatched`, so pr-merge.yml's
  post-merge-dispatch job knows which re-run is its to start.
- A `pr-merge-dispatched-<id>` or `pr-merge-rerun-<id>-attempt-2` record now counts only when the
  run that uploaded it was started by an event of the job that writes it (`schedule`,
  `workflow_dispatch`, and `push` for the dispatch record), its `head_repository` is this
  repository, and its `head_sha` is on the judged branch's tip as `refs/heads/` names it, never a
  same-named tag. Before, a fork pull request from its own
  `main` could add its own pr-merge.yml and upload either record, and a tag named like the branch
  could too: a forged re-run record turned a red run into a flake, and a forged dispatch record
  verified a merge and named a run for the lane to re-run.
