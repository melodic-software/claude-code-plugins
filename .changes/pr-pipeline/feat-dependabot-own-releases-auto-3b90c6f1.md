---
bump: minor
---

### Changed

- The Dependabot tier rule reads the standards Dependabot policy's `fastTrack.own`: a pull request whose every update it names (this organization's own releases) skips the Actions publisher rule, and below 1.0 only its first version component counts, so a `melodic-software/ci-workflows` 0.x minor bump is tier `auto`. pr-unblock's `dependency-classify.mjs` reads the policy at the base; pr-merge reads it at the base and at the default branch head, and both copies must name every update.
