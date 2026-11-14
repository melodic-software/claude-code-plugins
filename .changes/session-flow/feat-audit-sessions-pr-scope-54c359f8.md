---
bump: minor
---

### Added

- **audit-sessions looks back over one pull request.** The new `pr --number <n> --repo <owner/repo>` action finds every session that linked the PR or ran on its head branch in its repository, subagent transcripts included, measures them, reads them in fresh subagents sized so none overfills its context, and hands that PR's review comments, open or merged and in any repository, to `/corrections:codify reviews --pr <n> --repo <owner/repo>` when the `corrections` plugin is installed; for a PR outside the current checkout's repository that action lists the lessons and proposes nothing. The store now records subagents' branches and PR links apart (`branches_sub`, `prs_sub`), so the next collect re-reads every transcript once. `retro` stays single-session and names this action for a pull-request retro.

### Changed

- **retro states when a change may skip approval.** Phase 4 now says a change is applied without the person's approval only where an evaluation set scores the changed surface and the change does not lower its score; until then every change waits for approval.
