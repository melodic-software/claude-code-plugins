---
bump: minor
---

### Added

- `/code-tidying:audit-comment-residue`, `audit-dead-code`, `batch-simplify`, `remove-comments` and
  `tidy` run across several repositories when `--repo`, `--repos-from`, `--owner` or `--fleet`
  names them, per the shared target-scope contract (`reference/target-scope.md`): one pass per
  repository, findings merged on one scale, and each repository's writes and state kept in that
  repository. With no target form, each skill works as before.
- `dead-code-scan.sh --root <dir>` scans the repository that holds `<dir>` instead of the working
  directory's.
