---
bump: minor
---

### Added

- The `external-agents` plugin: hands tasks and reviews to other vendors' official coding-agent CLIs through their documented headless surfaces, Codex first. This release ships the `external-agents` command (`run`, `review`, `status`, `result`, `cancel`, and `update`, which reports a CLI's version, login and latest release, caches its help per version, and checks its docs index and the config keys the runner passes), the team config schema for `<home>/external-agents.yaml`, and the Codex prerequisite with its daily latest-release check. Every run passes the mode's sandbox and never an approval bypass; a briefed review names its merge base and changed files; a run whose commands the sandbox refused is recorded `blocked-by-mode`, not `ok`; a CLI that is missing, logged out or over its usage limit is refused until its next trial time; `cancel` and the run timeout stop the whole process tree. It replaces OpenAI's `codex@openai-codex` plugin once the runner and the Codex skill land.
