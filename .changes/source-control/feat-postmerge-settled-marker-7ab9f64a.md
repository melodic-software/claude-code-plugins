---
bump: minor
---

### Added

- The post-merge check (`babysit_postmerge.py`) settles a lane merge it judged verified. A check whose read was complete lists, in its report's `settle`, each of the agent identity's merges that is verified with no red, superseded or flaked full run and no running canary in its window and no empty record listing behind it. `--settle-from <report>` then posts the identity's `<!-- babysit-merge-settled sha=<merge commit> -->` comment on each one's pull request. A later check counts a merge that carries that marker, unedited and written by the identity, as verified without reading its runs or its `pr-merge-dispatched-<id>` artifact. The same author and edit checks as the pin comment decide whether a marker counts. The marker is read in the same batched comment query as the pins, and the run listings start at the earliest merge not yet settled, so a settled merge no longer fails once its record's 30-day retention ends; a merge never settled still depends on it. A failed post is a warning and changes no verdict, and the next check lists the merge again.
