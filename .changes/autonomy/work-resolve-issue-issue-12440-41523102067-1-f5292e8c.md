---
bump: patch
---

### Fixed

- `check-security-binding.mjs` evaluation mode now counts a contrary event in a cell's promotion epoch when its `discovered` time is at or after the cell's `ratified_at`, even if its `at` is earlier. Before, an event with a backdated `at`, such as a revert's committer date, was dropped as pre-epoch. An event with no `discovered` is still assigned by its `at`. An event dated before `ratified_at` whose `discovered` does not parse now counts as contrary, so the check fails closed.
