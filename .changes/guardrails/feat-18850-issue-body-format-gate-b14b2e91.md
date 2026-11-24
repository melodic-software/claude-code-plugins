---
bump: minor
---

### Added

- `block-body-format-violation` now refuses a `gh issue create`, or a GitHub MCP `create_issue` or `issue_write` create, whose body completes no issue kind the target repository declares in `issue_body_required_sections`: a required `##` or `###` heading missing, empty, or answered `_No response_`. It names the closest kind and each heading to add. A repository that declares no issue format is not judged; `issue_body_format_gate: false` turns the check off.
