---
bump: minor
---

### Added

- A `pre-push-content` git-hook entry runs the `pre-commit-content` secrets and machine-specific path scan at push time, on every pushed ref. It covers commits the commit-time check never judged: commits made before the hooks were installed, commits from a tool or clone without them, and commits rebased or cherry-picked in. Each pushed commit is judged on the lines it adds to its parent, so a token that one commit adds and a later commit of the same push removes still fails the push. A merge is judged on the lines it adds against every parent. Commits a remote-tracking ref already holds are not judged again. Each finding names its commit. The entry honors `checks.guardrails.pre-push-content.declined`, and the lefthook remote runs it as a second sequential `pre-push` job.

### Changed

- `pre-commit-content` now runs its scan from `git-hooks/content-scan.sh`, which `pre-push-content` shares; installs copy that file beside the entry as an asset. What it judges and reports is unchanged.
- The setup skill's lefthook guidance now says that lefthook gives the pushed refs to every `use_stdin` job while the `pre-push` jobs run one after another, and that under `parallel: true` the jobs read one shared stream.
