---
bump: minor
---

### Added

- `/verification:confirm outcome` on a branch other than the default branch, for a change E2E applies to, calls `/app-control:map refresh <control skill dir>` once when `affected.json` names no touched feature but lists unmatched changed files, so a feature the change adds is mapped on the ticket branch instead of only reported as not mapped.
