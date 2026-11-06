---
bump: patch
---

### Fixed

- stop ship run at entry when the implementation plugin is missing

  /work-items:ship run hands every item to
  /implementation:implement-dispatch. When the implementation plugin is
  not installed, it now stops before any claim and tells the user to
  install it, instead of claiming items it cannot dispatch.
