---
bump: minor
---

### Added

- **`codify reviews --pr <n> [--repo <owner/repo>]` mines one chosen pull request.** Open PRs are included. The `review_mining_prs` window is not read and the distinct-PR threshold does not apply: every lesson goes on, labeled as from one pull request, and its proposal still waits for the person's approval. When `--repo` is not the current checkout's repository, the lessons are listed with their repository and PR and nothing is counted, proved or proposed, since those steps need that repository's checkout. The bare `reviews` form is unchanged.
