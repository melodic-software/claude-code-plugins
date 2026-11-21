---
bump: minor
---

### Added

- The `external-agents` plugin: hands tasks and reviews to other vendors' official coding-agent CLIs through their documented headless surfaces, Codex first. This release ships the `external-agents` command (`run`, `review`, `status`, `result`, `cancel`), the team config schema for `<home>/external-agents.yaml`, and the Codex prerequisite with its daily latest-release check. Every run passes the mode's sandbox and never an approval bypass; a run whose commands the sandbox refused is recorded `blocked-by-mode`, not `ok`; a CLI that is missing, logged out or over its usage limit is refused until its next trial time; `cancel` and the run timeout stop the whole process tree. It replaces OpenAI's `codex@openai-codex` plugin once the runner and the Codex skill land.
