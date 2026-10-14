---
bump: minor
---

### Changed

- `explain`, `illustrate` and `quiz-me` have shorter descriptions and bodies, `teach` has a one-line description and a shorter body, and `setup` has a one-line description. Outcome eval cases, and trigger probes held out from the rewriter, measured each change against the old text before it shipped.

### Added

- Eleven outcome eval cases under `evals/` (`ex-`, `il-`, `qz-`, `te-`, `su-`), and frozen trigger-probe sets for `explain`, `illustrate` and `quiz-me` under `probes/`.
