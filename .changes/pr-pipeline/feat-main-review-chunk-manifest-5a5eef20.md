---
bump: minor
---

### Added

- A chunked pr-review-main prompt lists every file of the whole diff, one line each with its chunk, its status (added, modified, deleted, or renamed with its old and new path) and its path, up to 20000 bytes of lines with the rest counted. Each chunk's reviewer reports a change that references a file another chunk holds as a finding naming both paths, so a dependency across chunks reaches the summed verdict. A one-chunk prompt is unchanged, byte for byte. The `pr-review-main chunks` notice adds `manifest_paths=<n>`, the files that list names (0 for one chunk).
