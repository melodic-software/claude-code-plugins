---
bump: patch
---

### Fixed

- Shared `check-lib.sh` synced where this plugin carries it: the changed-line ranges no longer count an added line whose text without whitespace equals a line the same file's diff removes, so a formatter that only reindents a file, or a move within the file, adds no line to judge. A new, reworded or duplicated line, and one moved in from another file, still counts.
- The pre-commit and pre-push content scans therefore pass a reindented line holding a pre-existing machine-specific path or secret pattern, and still block one the change adds.
