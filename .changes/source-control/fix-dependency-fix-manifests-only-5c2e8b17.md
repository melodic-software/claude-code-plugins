---
bump: patch
---

### Changed

- `/source-control:pull-request dependency --ci` chooses `fix` only for a change to npm or pip manifests and lockfiles in a directory `.github/dependabot.yml` lists, outside `.github/`, and `escalate` for a fix that needs any other file.
