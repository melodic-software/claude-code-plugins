---
bump: patch
---

### Fixed

- `babysit_postmerge.py` counts a `github-actions[bot]` attempt 2 of a full run the pr-merge lane
  dispatched when pr-merge.yml's own `pr-merge-rerun-<run id>-attempt-2` record backs it: an
  artifact uploaded by a pr-merge.yml run on the judged branch of this repository, not a
  `pull_request_target` run. Green on that attempt is a flake; red is a failure. Without the
  record, with a record for another run or attempt, or when a person started attempt 2, it still
  reads red. A failed read of the record makes the verdict unreadable (exit 3).
- Its report marks each red full run awaiting its re-run with `laneDispatched`, so pr-merge.yml's
  post-merge-dispatch job knows which re-run is its to start.
