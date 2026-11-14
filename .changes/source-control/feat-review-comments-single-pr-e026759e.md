---
bump: minor
---

### Added

- **`pull-request review-comments --pr <number>` reads one chosen pull request.** It prints the same rows as `--prs <n>` for that PR alone, open PRs included (where the PR author's own comments are always dropped), with `--repo` as before. `--prs <n>` is unchanged; passing both is a usage error.
