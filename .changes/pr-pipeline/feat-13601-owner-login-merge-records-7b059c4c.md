---
bump: minor
---

### Added

- `post-merge.paths` names post-merge accounting paths besides the lanes App's. This repository sets `owner-agent`, mode `record`, for agent sessions merging through the owner login (a pull request whose body carries a session marker or the Claude Code footer and whose commits carry a `Co-Authored-By: Claude` trailer). On each canary push run, post-merge-demotion-alert labels such a merge `merge-path:owner-agent` and a revert of one `post-merge:reverted`, and files no issue, demotes nothing, trips no revert breaker and holds no pull request. `merge-path.mjs rollup` prints merges, reverts and escaped defects per path for a window (README.md, "Merge paths").
