---
bump: patch
---

### Fixed

- The git hook check now fails, naming the tool and saying the change was not fully checked, when git or awk fails while it lists the changed lines or filters findings to them. A crashed awk run used to leave every finding filtered out and the hook passing.
