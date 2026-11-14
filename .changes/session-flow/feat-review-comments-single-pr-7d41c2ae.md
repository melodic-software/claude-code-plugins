---
bump: minor
---

### Changed

- **`audit-sessions pr` hands over that pull request's own review comments.** It now calls `/corrections:codify reviews --pr <n> --repo <owner/repo>` for an open or merged PR in any repository, in place of the last merged PRs of the current checkout. For a PR outside the current checkout's repository that action lists the lessons and proposes nothing.
