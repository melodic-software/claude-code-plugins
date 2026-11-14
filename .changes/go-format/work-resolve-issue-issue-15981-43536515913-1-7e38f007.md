---
bump: patch
---

### Fixed

- A merge commit no longer formats or lints the files the merge takes unchanged from another parent: the pre-commit file list skips a path whose staged entry equals a merge head's. Installed hooks report drift until reinstalled. A merge the old hook already formatted keeps those files listed; restore them from the merge head or redo the merge.
