---
bump: patch
---

### Fixed

- `/source-control:babysit-prs`: the verdict gate's kept-answer key now probes the admission rules at the repository's default branch, the branch the verdict read takes `task-list` from, rather than at the pull request's base. For a stacked pull request, a change to the default branch's admission rules now moves the key, so a kept answer computed under the old `task-list` is no longer reused. The trusted-actor probe still reads at the pull request's base.
