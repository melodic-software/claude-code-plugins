---
bump: minor
---

### Changed

- `/review:merge-risk` `--dir` mode also reads a diff cut into chunks of part files (`<dir>/chunks.json`). With more than one chunk it rates through agents dispatched at once, a rater and a blind checker per chunk, takes the highest level per area on each side, and adds a HIGH `Diff coverage` row for any chunk left out or any part an agent could not read, so a rating never claims a diff it did not read.
