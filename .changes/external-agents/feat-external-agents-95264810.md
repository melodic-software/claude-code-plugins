---
bump: minor
---

### Added

- The `external-agents` plugin: hands tasks and reviews to other vendors' official coding-agent CLIs through their documented headless surfaces, Codex first. This release ships the scaffold: the `external-agents` command (usage only for now), the team config schema for `<home>/external-agents.yaml`, and the Codex prerequisite with its daily latest-release check. It replaces OpenAI's `codex@openai-codex` plugin once the runner and the Codex skill land.
