# Changelog

All notable changes to the `external-agents` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0] - 2026-11-22

### Added

- Google Antigravity (`agy`) support: a provider record, the `antigravity` keys in `<home>/external-agents.yaml`, bundled defaults (every use read-only, council member on), and the agy prerequisite with its daily latest-release check. The `/external-agents:antigravity` skill drives the `external-agents` command for agy the way `/external-agents:codex` does for Codex. Read-only runs use agy's default approval mode through a per-run settings file, so writes and commands are refused and reported as blocked. Writes are opt-in through `antigravity.uses.task.mode: write`, because agy's auto mode, whose limit is agy's sandbox plus agy's own review, has no network isolation. With no `antigravity.model` set, agy's own default model runs. Every agy run passes `--disable-slash-commands`, so a prompt starting with `/` reaches the model as text, and a review warns when the branch changes agy's `.agents/` workspace configuration.

## [0.1.0] - 2026-11-22

### Added

- The `external-agents` plugin: hands tasks and reviews to other vendors' official coding-agent CLIs through their documented headless surfaces, Codex first. This release ships the `external-agents` command (`run`, `review`, `status`, `result`, `cancel`, and `update`, which reports a CLI's version, login and latest release, caches its help per version (from stderr when a CLI prints its help there, and reported when a help command prints nothing), and checks its docs index and the config keys the runner passes), the team config schema for `<home>/external-agents.yaml`, and the Codex prerequisite with its daily latest-release check. Every run passes the mode's sandbox and never an approval bypass; a briefed review names its merge base and changed files; a run whose commands the sandbox refused is recorded `blocked-by-mode`, not `ok`; a CLI that is missing, logged out or over its usage limit is refused until its next trial time; `cancel` and the run timeout stop the whole process tree. The `/external-agents:codex` skill drives the command: it runs a Codex task or investigation as a background job, resumes a thread, reviews a branch, and reads back `status`, `result`, `cancel` and `update`, with its first reply line naming the mode the job ran in, model and effort guidance as pointers to the Codex docs, and no model passed unless one is configured. It replaces OpenAI's `codex@openai-codex` plugin.
