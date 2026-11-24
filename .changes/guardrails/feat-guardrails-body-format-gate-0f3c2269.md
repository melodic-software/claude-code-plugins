---
bump: minor
---

### Added

- New guard `block-body-format-violation`: refuses a `gh pr create`, a `gh pr edit` with a body, or a GitHub MCP pull request create or update whose body breaks the format the target repository declares in `docs/conventions/source-control.yaml` (`pr_body_required_sections`, and the opener line where `linkage_gate_uses_pattern` matches a workflow), naming each missing or empty section and the line to add. A repository that declares neither key is not judged. Switches: `block_body_format_violation_enabled` (userConfig) and `pr_body_format_gate: false` in the repository's team file or git-ignored personal override.
