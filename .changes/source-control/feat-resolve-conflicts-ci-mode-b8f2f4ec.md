---
bump: minor
---

### Added

- `/source-control:resolve-conflicts ci` runs unattended for the pr-unblock lane: it resolves and stages each path with `git add`, never asks, commits, pushes or runs gates, never edits `.github/workflows/`, and escalates by leaving a path unstaged. The skill now grants read-only git commands and `git add` in `allowed-tools`.
