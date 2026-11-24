---
bump: minor
---

### Added

- `block-body-format-violation` refuses a pull request body (`gh pr create`, `gh pr edit` with a body, or a GitHub MCP pull request create or update) whose Loosened checks section is not empty unless an issue it links (by a closing keyword, or with none, by its one first-column `Refs:` issue) has a body holding the owner-decision record line link and the owner's words after the verbatim marker in double quotes. The heading, the record pattern and the marker come from the repository's `pr_body_loosened_checks_*` keys; a repository that sets none is not judged. It reads at most three linked issues with `gh api`, and an unreadable issue, or a linked issue past the third, passes with a warning.
