---
bump: patch
---

### Fixed

- Both activity runners run a script activity at the path `collect-base-activity`'s new `script-path` output names, not a staging layout of their own. The action loads from the base tip at job time while a dispatched run keeps its dispatch-time runner workflow, so a layout change merged mid-run made the runner exec a path the action no longer staged and failed the activity check unretryably.
