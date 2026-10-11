---
bump: patch
---

### Fixed

- **The instruction audit reads each model's default effort from the docs instead of a copied list.** The `high`-pin exemption listed the models whose default is not `high` and had fallen behind: Haiku 5.5 now defaults to `medium` too. The row now points at the per-model defaults in model-config, so the audit judges a `high` pin against the default the docs state for the resolved model.
