---
bump: minor
---

### Changed

- **The Dependabot tier reads the policy's `fastTrack.own`.** `babysit_dependabot.classify` takes each read policy copy's own globs (`own_globs`). A pull request whose every update both copies name (`all_own`, this organization's own releases) takes no `publisher:` reason, and a below-1.0 second-component move is not `major:` for it, so a `melodic-software/ci-workflows` 0.x minor bump sorts `auto`. A first-component move stays major. `dependabot_eligibility` reads the base and default-branch policy copies once and sorts the pull request again under them.
