---
bump: patch
---

### Changed

- Hold labels default to `needs-owner-decision` and `needs-reporter-info` only, the morning brief's default decision label is `needs-owner-decision`, and the triage skill applies the two labels by those names.

### Removed

- `status: needs-decision`, `status: needs-info` and `work-class: untrusted-provenance` no longer hold an item, along with `WIT_LEGACY_UNTRUSTED_LABEL` and `WIT_HUMAN_FLOOR_WORK_CLASS_LABELS`. A repository still using those labels sets `config.hold_labels` in its tracker binding or renames them.
