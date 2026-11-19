---
bump: minor
---

### Added

- **Several repositories in one run.** `/code-metrics:audit`, `audit-coverage`,
  `audit-duplication` and `audit-suppressions` take the target-scope forms (`--repo`,
  `--repos-from`, `--owner`, `--fleet`, `--skip`) and run once per repository from that
  repository's root, with one report section and one JSON document per repository. A repository
  other than the session's own is measured only when its checkout is clean at `origin/HEAD`, and
  then over its whole tree unless paths are named. Kept reports and `--findings` files stay with
  each repository. With no target form, nothing changes. The plugin now ships the target-scope
  contract as `reference/target-scope.md` and its own differences in
  `reference/several-repositories.md`.
