---
bump: minor
---

### Changed

- `/source-control:pull-request create` always opens the PR as a draft. When `pr_open_state` resolves to `ready` (a repository or user opts in; the default stays `draft`), it then runs `ready` on the new PR, so a PR reaches ready only through `ready`'s base merge, reviews and verify gate; a gate that stops leaves it a draft and the report says why. Unattended runs, `--pushed` included, still leave a draft. `create` reference §2.4.3 states what a save point, a draft and a ready PR each mean.

### Added

- A request level for `pr_open_state`: an invocation that asks for a draft, or names the PR a multi-session container, wins over every configured level and writes a `Draft:` line into the PR body. `/source-control:babysit-prs` never flips a draft carrying that line, in any tier.
