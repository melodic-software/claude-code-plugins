---
bump: minor
---

### Added

- New guard `block-lane-pr-disable-auto` on the Bash tool blocks `gh pr merge <n> -R <owner>/<repo> --disable-auto`, and the `disablePullRequestAutoMerge` mutation through `gh api graphql`, on a pull request the lanes App (`melodic-automation-lanes[bot]`) opened (#16484). A session runs under the owner's login, so the pr-merge lane read such a disable as the owner's veto and never armed the pull request again (#14799, #16372). The block says to hold the pull request with the `do-not-merge` label, which the lane disarms on and re-arms after by itself. A target the guard cannot read literally (a shell variable, `$(...)`, backticks, no PR number) is blocked; a pull request by any other author passes. Turn it off with `block_lane_pr_disable_auto_enabled`, on by default.
