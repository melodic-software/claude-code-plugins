---
bump: minor
---

### Changed

- `merge.dependabot.trusted-action-owners` lists `melodic-software` beside `anthropics`, so a Dependabot pull request that only moves this organization's own action pins (the `melodic-software/ci-workflows` composite actions) to a tagged commit skips `CI Status`'s trust-gate hold. An own release is this organization's code (owner decision 2026-11-15, the Dependabot policy's `fastTrack`).
