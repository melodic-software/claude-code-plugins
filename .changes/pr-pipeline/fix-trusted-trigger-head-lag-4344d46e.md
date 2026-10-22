---
bump: patch
---

### Changed

- `publish-feedback` counts a fix commit as touching a review thread on a skill's `SKILL.md` when it changes any file in that skill's directory (its `evals/` and `reference/` included), so a fix to a skill's evals no longer escalates `feedback-not-landed` (#8832). Every other thread still needs its exact path, and the range check is unchanged.
