---
bump: minor
---

### Changed

- `/review:explain-change` reads its team settings from `docs/conventions/review-digest.yaml`, validated by the new `schemas/review-digest.schema.json`. The `json config` block in `docs/conventions/review-digest.md` and `.claude/review-digest.json` are read only when the YAML file is absent from the base commit, for one release. `/review:setup apply` writes the file when the operator asks to change a digest setting.
