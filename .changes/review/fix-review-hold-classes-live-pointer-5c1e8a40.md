---
bump: patch
---

### Fixed

- `/review:code-review` and `/review:security-review` no longer copy the hold classes: they point at the live definitions in the compose step of [ci-workflows `pr-review-cli.yml` v0.65.8](https://github.com/melodic-software/ci-workflows/blob/v0.65.8/.github/workflows/pr-review-cli.yml#L1088-L1098). Neither returns a `trust-gate` hold, and spend that draws only on prepaid credit or a subscription is one summary line, not a hold or a counted finding. `/review:security-review` gives a changed file under the wrapper's trusted paths extra scrutiny.
