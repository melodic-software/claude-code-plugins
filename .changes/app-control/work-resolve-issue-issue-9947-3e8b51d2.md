---
bump: patch
---

### Fixed

- `/app-control:map refresh`: a pass now switches to the upkeep branch, creating it from the default branch or merging the default branch into it, before the source wave and the live pass, so its corrections describe the tree the upkeep pull request ships. The dirty-tree checks and their blocked outcomes, and a legacy conversion's dirty-map check and attended ask, run before that switch, a refused merge is aborted, and a ticket-branch pass still stays on its branch. Every pass, blocked early or not, switches back to where it started, and a clean pass records its skip state only after that return.
