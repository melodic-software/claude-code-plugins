---
bump: patch
---

### Changed

- The `setup` skill's Gotchas again warn against regenerating the whole config to change one key, and against moving the eval-fixture exclusion into the script. Their removal shipped on an eval that a negative control showed cannot tell the body from one with its procedure sections emptied, so the cut was never measured.
