---
bump: minor
---

### Added

- `block-unresolved-pr-merge` guard (#6463): blocks a pull-request merge while the PR has an unresolved review thread, a changes-requested review, or a failed check, and blocks an immediate merge on pending checks. It matches `gh pr merge` (`--admin` and `--auto` included), a `PUT` to the REST merge route or the Claude Code cloud `ccr/auto_merge` route through `gh api` or `curl`, the GraphQL merge, auto-merge and merge-queue mutations, and an MCP `merge_pull_request` or `enable_pr_auto_merge` tool. PR state is read over REST, with review threads from GraphQL or, where GraphQL is refused, the cloud `ccr/review_threads` route. It fails open with a visible notice when `gh` is missing, a read fails or its 35 s read budget runs out, except that a GraphQL merge mutation whose pull request cannot be resolved is blocked. Off switch: `block_unresolved_pr_merge_enabled`.
