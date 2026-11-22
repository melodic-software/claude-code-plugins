---
bump: patch
---

### Fixed

- Creating a tracker item, with or without `--repo`, now exits `3` when GitHub reports you cannot push to the resolved repository, so someone else's public repository never receives your issues. Reads and lists there still resolve.
