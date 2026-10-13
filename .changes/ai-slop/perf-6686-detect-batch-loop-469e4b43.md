---
bump: patch
---

### Changed

- **`/ai-slop:audit` detection is much faster on a large tree.** `detect.sh` now extracts prose for every target in one awk pass and runs each rule as one grep over all files, instead of forking a pipeline per file per rule. Findings and summary output are unchanged, and stderr notes for NUL bytes and unreadable files are reworded; the process count no longer grows with the number of files.
