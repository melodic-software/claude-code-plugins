---
bump: minor
---

### Added

- **audit-sessions looks back over one pull request.** The new `pr --number <n> --repo <owner/repo>` action finds every session that linked the PR or ran on its head branch in its repository, subagent transcripts included, measures them, reads them in fresh subagents sized so none overfills its context, and hands review comments to `/corrections:codify reviews` when the PR is merged, is in the current checkout's repository, and the `corrections` plugin is installed. The store now records subagents' branches and PR links apart (`branches_sub`, `prs_sub`), so the next collect re-reads every transcript once. `retro` stays single-session and names this action for a pull-request retro.

### Changed

- **retro states when a change may skip approval.** Phase 4 now says a change is applied without the person's approval only where an evaluation set scores the changed surface and the change does not lower its score; until then every change waits for approval.
