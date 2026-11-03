---
bump: patch
---

### Fixed

- Closing an item through `/work-items:triage` or `/work-items:track done` first moves each open item it blocks onto the item that now carries the work (for a duplicate, the surviving item), then drops the old edge, so a close no longer frees work still waiting on a prerequisite; a won't-fix close keeps its edges and names its dependents for re-triage.
