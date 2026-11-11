---
bump: patch
---

### Fixed

- A demotion record's lift by a referencing pull request now also counts an upper layer of a native stack into main. Such a layer keeps the lower layer's branch as its base when the stack lands together, so the lift reads its `stack.baseRefName` beside `baseRefName`; its merge commit must still be on main.
