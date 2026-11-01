---
bump: patch
---

### Fixed

- The git hook check now fails, naming the tool and saying the change was not fully checked, when git or awk fails while it lists the changed lines or filters findings to them. A crashed awk run used to leave every finding filtered out and the hook passing.
- A push over a remote commit this clone has not fetched is checked from its merge-base with the default branch, with a notice saying to fetch, instead of failing on the missing object.
