---
bump: minor
---

### Changed

- `merge.diff-check.floor-paths` returns with a new shape: class-tagged rows (`glob`, `class`, and on a `gate` row an optional `author-lift: false`), joined to the built-in path floor. The plain-string list the key held until it was removed fails validation, and a row the loader cannot use turns the rung off. This repository's own floor paths move there, and its effective floor is unchanged.
