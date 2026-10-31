---
bump: patch
---

### Changed

- `reference/config-resolution.md` "Drafting vs enforcement" records that commit-subject enforcement falls back to the operator's git-ignored `docs/conventions/source-control.local.yaml` `subject_pattern` where the team layer sets none, never merged with a team pattern, and that drafting does not read that file.
