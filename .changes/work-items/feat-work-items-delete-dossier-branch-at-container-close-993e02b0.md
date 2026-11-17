---
bump: minor
---

### Added

- The container close ritual now deletes the container's dossier branch, and the dossier branch its source wayfind map names, once the close-out review passes. It validates a branch name read from a comment, skips a branch with an open pull request, and when attended shows each branch's commits and files not on the default branch before asking once. An unattended run never deletes: it lists each branch due for deletion in the closing comment and its report. A container that stays open deletes nothing, and the closing comment reports each branch.
