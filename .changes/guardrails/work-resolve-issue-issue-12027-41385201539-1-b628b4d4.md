---
bump: patch
---

### Fixed

- **block-unresolved-pr-merge**: a PR that fixes a broken reusable workflow or action can be merged again. When the PR's diff changes a file under `.github/workflows/` or `.github/actions/`, the guard reports a failing check that the base branch's rules do not require as a warning and does not block on it, when the check's GitHub Actions run shows it loaded the base branch's copy: a reusable workflow the PR changes, or, for a changed action, one of the repository's own reusable workflows, called at the base branch. Such a check may still run the base branch's broken copy. A failing check still blocks when it is required, when it is a commit status, when its run's own workflow file is one the PR changes or it loaded a changed workflow from the PR's head, since the PR's own copy then ran, or when its run cannot be read. When the changed files or the base branch's rules cannot be read, or the rules require no check, every failing check blocks as before. Unresolved review threads and change requests still block in every case.
