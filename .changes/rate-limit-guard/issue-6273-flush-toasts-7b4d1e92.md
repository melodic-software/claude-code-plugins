---
bump: patch
---

### Fixed

- A throwing transcript log no longer drops the rest of a window-change flush: each item now has its own try/catch, so only the failing line is lost and the other windows' lines, toasts and the notice row still arrive.
