---
bump: patch
---

### Changed

- Trimmed frontmatter descriptions across all 4 `docs-naming` skills (2,364 -> 1,187 chars, -1,177 / -49.8%): `audit-file-names` (486 -> 345), `generate-file-name-gate` (677 -> 380, routing auditing to `audit-file-names` and renaming to `realign-file-names`), `realign-file-names` (470 -> 325), and `setup` (731 -> 137, `disable-model-invocation: true`), while preserving read-only/per-file-acceptance/no-overwrite safety postures and sibling exclusions.
