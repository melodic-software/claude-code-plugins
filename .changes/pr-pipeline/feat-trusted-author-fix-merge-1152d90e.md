---
bump: minor
---

### Changed

- Adoption covers every account on `.github/standards/trusted-actors/trusted-actors.json`, people
  and Apps alike, matched by id (owner decision 2026-10-22): fix-ci fixes a red PR the release
  App, the owner or anyone later added to the list opened, and `merge.verify-authors:
  lane-or-owner` judges it. An App's PR is adopted at once; a person's still waits
  `adoption.idle-hours`. Dependabot's red PRs stay with review-dependency.
- The verifier reads a trusted author's PR title and body as intent alongside the spec, and fails
  a lane fix that changes behavior or intent, which escalates the PR to a person.

### Removed

- `adoption.owner-ids`: the trusted-actor list is the one source. Without `adoption.idle-hours`
  nothing is adopted.
