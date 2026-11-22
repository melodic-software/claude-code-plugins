---
bump: patch
---

### Fixed

- In a fork checkout, the GitHub tracker adapter no longer follows `gh`'s default repository, which a stock `gh repo clone` of a fork records as upstream. With no `--repo`, it resolves the repository with the same `target-repo.sh` that `/source-control:pull-request` uses (canonical `lib/target-repo.sh`): the pushable fork wins, and remotes naming two or more GitHub repositories with no fork and no `gh repo set-default` exit `3` with that fix, instead of creating or listing items on whichever repository `gh` picks by remote name. Each resolution prints `target repository: <owner>/<repo>` on stderr.
