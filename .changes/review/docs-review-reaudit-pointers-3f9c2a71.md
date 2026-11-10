---
bump: patch
---

### Changed

- Skill bodies point at the live upstream sections for bundled-review, managed-service, workflow,
  nesting and model-guidance specifics instead of restating them, each with an as-of date and a
  recheck trigger.
- `setup` now lists `docs/conventions/review-digest.yaml` among the files it may write, and
  `explain-change` states why a view answer is capped at 4000 characters.
