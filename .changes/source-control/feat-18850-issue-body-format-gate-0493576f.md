---
bump: minor
---

### Added

- New keys `issue_body_required_sections` (a mapping of issue kind to required headings, or `none`) and `issue_body_format_gate` (boolean, default `true`) in `docs/conventions/source-control.yaml` and its personal override, read by the guardrails plugin to refuse an issue body that completes no declared kind.
