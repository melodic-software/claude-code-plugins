---
bump: patch
---

### Fixed

- **block-unresolved-pr-merge**: a PR that fixes a broken reusable workflow or action can be merged again. When the PR's diff changes a file under `.github/workflows/` or `.github/actions/`, the guard reports a failing check that the base branch's rules do not require as a warning and does not block on it. Such a check may still run the base branch's broken copy. A failing required check still blocks. When the changed files or the base branch's rules cannot be read, or the rules require no check, every failing check blocks as before. Unresolved review threads and change requests still block in every case.
