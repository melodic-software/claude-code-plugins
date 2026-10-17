---
bump: patch
---

### Fixed

- **`block-unresolved-pr-merge` no longer blocks on a matrix job cancelled before its matrix expanded (#7797).** Such a run carries the bare job name (`test-bash`), while the next run's legs carry `test-bash (0)`, so the two never grouped and the cancelled run counted as failing. A cancelled newest run is now superseded by a newer check run of the same app, in another check suite, named `<name> (...)`; a sibling in the same workflow run never clears it. An unrelated workflow's `<name> (...)` job in another suite also clears it, which the check-runs payload cannot tell apart from a matrix leg. A failing leg still blocks under its own name, and a cancelled run with no newer leg still blocks. Not covered: the reverse shape, an older cancelled `name (0)` followed by a newer bare `name`, which has not been observed.
