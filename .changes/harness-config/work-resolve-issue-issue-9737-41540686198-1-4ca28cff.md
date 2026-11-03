---
bump: major
---

### Removed

- **audit:** the one-release read of `.claude/audit-pass.md` as the team suppression layer. The team layer is only the `suppressions` mapping of `<home>/harness-config.yaml`; with that file absent the team layer is absent, and an old `.claude/audit-pass.md` is neither read nor listed in `suppressions.layers`. A repository that still keeps its suppressions there moves each entry, unchanged and with the `anchor/v1` key and each `date` quoted, under `suppressions:` in `<home>/harness-config.yaml`, then deletes the old file.
- **setup:** `check` no longer reports the old team file, and `apply` no longer writes the team YAML from it.
- **audit, audit-pass:** the skills and the suppression reference no longer describe the compatibility read.
