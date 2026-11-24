---
bump: patch
---

### Fixed

- Shared `check-lib.sh` synced where this plugin carries it: the changed-line ranges no longer count an added line whose text without whitespace equals a line the same file's diff removes, so a formatter that only reindents a file, or a move within the file, adds no line to judge. A new, reworded or duplicated line, and one moved in from another file, still counts.
