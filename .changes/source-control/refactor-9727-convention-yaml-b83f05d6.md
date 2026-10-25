---
bump: minor
---

### Added

- `docs/conventions/source-control.yaml` accepts `dialect`, the regex dialect of `subject_pattern` and `pr_title_pattern` (default `posix-ere`), so every key of the folder-form `commit-convention.yml` fits in the one team file. The guardrails convention gate reads it and turns its enforcement off for any other value.
