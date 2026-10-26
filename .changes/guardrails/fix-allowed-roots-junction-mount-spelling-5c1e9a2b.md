---
bump: patch
---

### Fixed

- `secret_pattern_detection_allowed_roots` now grants a Windows write whose path reaches an allowed root through a junction into the temp folder, as it does on Linux. Git Bash answers such a junction in the `/tmp` mount spelling, and the long drive spelling of that answer is now taken from the existing ancestor alone, before the components still to be created are joined. A path that resolves outside every root, or that cannot be resolved, is still scanned.
