---
bump: minor
---

### Added

- The `visualize` skill's `excalidraw-file` target starts a diagram from a bundled shape palette,
  `templates/shape-palette.excalidraw`. The palette holds a lane frame, a step, a decision, a start
  or end, an arrow, a divider line and a note. The skill copies the elements it needs into the new
  diagram, then runs the existing check and write steps.
