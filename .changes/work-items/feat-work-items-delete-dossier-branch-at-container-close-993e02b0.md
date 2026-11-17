---
bump: minor
---

### Added

- The container close ritual now deletes the container's dossier branch, and the dossier branch its source wayfind map names, once the close-out review passes. It validates a branch name read from a comment, skips a branch with an open pull request, asks once when attended, deletes nothing when unattended or when the container stays open, and reports each branch in the closing comment.
