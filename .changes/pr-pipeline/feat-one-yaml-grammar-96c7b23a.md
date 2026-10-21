---
bump: major
---

### Changed

- **BREAKING:** `models.profiles`, the `models.issue-dimensions` option maps and `models.issue-dimensions.sizes` are written in block style, one key per line, in `docs/conventions/pr-pipeline.yaml` and in `examples/claude-code-plugins.yaml`. Values and key types are unchanged. The shared YAML-subset reader that `set-dimensions.sh` and `scripts/check-convention-yaml.sh` use now refuses flow mappings, so a consumer's `pr-pipeline.yaml` that writes these maps as `{ ... }` must rewrite them in block style.
