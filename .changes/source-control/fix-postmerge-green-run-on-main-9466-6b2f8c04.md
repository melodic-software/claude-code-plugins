---
bump: patch
---

### Fixed

- The post-merge check takes the newest green full run for a red run's affected set (`_Context.affected`) and the newest completed run for its baseline (`_Context._baseline`). It now picks only a run whose head commit is the branch's tip or an ancestor of `refs/heads/<branch>` (`_Context.on_branch`, through `_Context.contains`). The same check now filters the scheduled, dispatched and canary runs a merge is judged on, the runs read by commit to prove a listing incomplete, and the lane re-run probe, so a red run on such a tag can no longer fail a merge. Before, it trusted any run that reported `head_branch: main`, and a run on a tag named `main` reports that too. Such a run could check out a writer's own commit and run its plan script, or narrow the affected set so that a red main run read as unaffected and filed no demotion.
