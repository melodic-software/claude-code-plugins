---
bump: patch
---

### Security

- `resolve-conflicts-select`, `address-feedback-select`, `review-dependency-select` and `fix-ci-context` in `pr-unblock.yml` fail on a PR whose head is in another repository, before it writes any head output, so a hand dispatch of a fork's PR posts no status on that head.
