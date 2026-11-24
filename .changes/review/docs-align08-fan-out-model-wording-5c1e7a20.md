---
bump: patch
---

### Changed

- `fanout_diversity: model` text names what it spreads over as fan-out models, not model tiers,
  since capability tier is the glossary word for frontier, strong and fast. The
  `review:fanout-sweep` workflow returns the list under `fanoutModels` in place of `tiers`, and
  its fallback log line says `fan-out model(s)`. The `model` config value is unchanged.
