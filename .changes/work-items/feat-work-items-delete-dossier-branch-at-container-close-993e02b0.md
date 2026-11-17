---
bump: minor
---

### Added

- The container close ritual now deletes the container's dossier branch, and the dossier branch its source wayfind map names, once the close-out review passes. It reads the branch prefix from the repository's `docs/conventions/source-control.yaml` and validates a branch name read from a comment. More than one matching branch, or a branch that heads an open pull request, is only reported: never deleted, asked about or offered for deletion in that run. `/work-items:ship` now routes the close to the ritual's file directly and names the dossier-branch step as part of that close. When attended, it shows each branch's commits and files not on the default branch before asking once. An unattended run never deletes: it lists each branch due for deletion in the closing comment and its report. A container that stays open deletes nothing, and the closing comment reports each branch.
