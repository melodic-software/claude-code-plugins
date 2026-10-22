---
bump: minor
---

### Added

- `adoption.spec-from-body-apps`: the App ids whose PR bodies a script writes (the release App
  and the standards-sync App here). An adopted PR that closes no issue is judged against its own
  title and body when a person or one of these Apps opened it; resolve-pr hands the verifier that
  text as the spec, and the verdict records `intent: pull-request`. Any other App, the lanes App
  included, still needs a closing issue, since a model that wrote the diff would also have
  written its spec.

### Changed

- Adoption covers every account on `.github/standards/trusted-actors/trusted-actors.json`, people
  and Apps alike, matched by id (owner decision 2026-10-22): fix-ci fixes a red PR the release
  App, the owner or anyone later added to the list opened, and `merge.verify-authors:
  lane-or-owner` judges it. An App's PR is adopted at once; a person's still waits
  `adoption.idle-hours`. Dependabot's red PRs stay with review-dependency.
- The verifier fails a change that alters behavior or intent the spec does not ask for, a lane's
  CI fix included, which escalates the PR to a person.

### Removed

- `adoption.owner-ids`: the trusted-actor list is the one source. Without `adoption.idle-hours`
  nothing is adopted.
