---
bump: minor
---

### Added

- `landed-work.sh --merged-heads-file <path>` reads TSV lines `<branch>\t<headRefOid>\t<baseRefName>` for merged pull requests and reports a row `landed` (method `merged-pr-head-exact`) only when the worktree is on that branch, its full HEAD equals `headRefOid`, and `baseRefName` is the base the engine resolved for the row. A squash-merged branch whose paths the base changed later no longer reads `STRANDED` or `UNKNOWN`, with no network call. Any other line changes nothing, and a dirty tree with a matching line reads `dirty`. The worktree `status` and `cleanup` contexts write the file from the same per-branch pull request reads as `--merged-refs-file`, which is unchanged.
