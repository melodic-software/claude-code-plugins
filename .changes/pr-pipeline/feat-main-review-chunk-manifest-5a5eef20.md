---
bump: minor
---

### Added

- A chunked pr-review-main diff writes `manifest.txt` in the review's data directory, every file of the whole diff one line each with its chunk, its status (added, modified, deleted, or renamed with its old and new path) and its path, up to what one Read returns whole with the rest counted. Each chunk's prompt names that file for the reviewer to read as untrusted data, so the paths the pull request's author chose never enter the prompt, and asks for a finding naming both paths when a change references a file another chunk holds, so a dependency across chunks reaches the summed verdict. A one-chunk prompt is unchanged, byte for byte. The `pr-review-main chunks` notice adds `manifest_paths=<n>`, the files the manifest names (0 for one chunk).
