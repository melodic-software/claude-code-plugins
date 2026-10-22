---
bump: patch
---

### Changed

- `/source-control:pull-request dependency --ci` chooses `fix` only for a change to npm or pip manifests and lockfiles in a directory `.github/dependabot.yml` lists, outside `.github/`, and `escalate` for a fix that needs any other file.

### Fixed

- The pr-merge lane no longer counts a lanes App `[dependabot skip]` commit as checked: on a
  Dependabot pull request each such commit must change only npm or pip manifest and lock files
  outside `.github/` that `.github/dependabot.yml` lists, as regular files, by a version change,
  or the merge is refused with `dependabot-fix-content:<why>`.
