---
bump: minor
---

### Changed

- The merge gate's review evidence (`babysit_gh.collect_lane_runs`, `babysit_review_evidence.bind`), its cost-decision carry and its lane-comment check also accept a run of a review caller's `workflow_run` lane. The run is found through the index check run on each head and bound on its own record: path, event `workflow_run`, head branch `main`, both repositories, and run-name `<name> #<pull request> <head sha>`. A bound lane run is read as a run on the head its run-name names, with that commit's tree, and stands in for the head's `pull_request` run. No lane run exists yet, so verdicts are unchanged.
