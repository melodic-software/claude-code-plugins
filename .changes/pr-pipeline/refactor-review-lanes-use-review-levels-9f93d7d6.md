---
bump: patch
---

### Changed

- The hosted review callers (`pr-review-hosted.yml`, `pr-review-security-hosted.yml`) no longer
  resolve a model. They pass `pr-review-cli.yml` no model, effort or turn budget and run its default
  `standard` review level, the same Opus at effort `high` and 75 turns. The `review-code` and
  `review-security` routes stay for `pr-review-main.yml`.
