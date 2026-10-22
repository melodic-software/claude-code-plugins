---
bump: patch
---

### Fixed

- A tap counts as dead even when the page's own polling redraws it

  In a shared interview, the page's tap telemetry no longer treats its own
  1.5 s state poll redraw as the answer to a tap. A tap that changes
  nothing is counted as dead however busy the page or the device is, while a
  tap that opens a sheet or runs an action is still answered.
