---
bump: patch
---

### Fixed

- `pr-feedback-dispatch.yml`'s `rerun-ci-status` job also re-runs a head's `ci-status` when a `pr-unblock.yml` run completes after setting or clearing a `pr-unblock/*` status on it, and when a person on the trusted-actor list approves it. Before, both changes waited for a hand re-run: the status is written with a `GITHUB_TOKEN`, whose events start no workflow, and no `pull_request` event fires on a review.
- The new `pr-review-approved.yml` relays an approving review of a same-repository pull request, with no permission, as a `workflow_run` upstream, so the re-run it causes is recorded for pr-verify's trigger gate.
