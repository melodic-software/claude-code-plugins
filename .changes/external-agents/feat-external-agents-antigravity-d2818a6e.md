---
bump: minor
---

### Added

- Google Antigravity (`agy`) support: a provider record, the `antigravity` keys in `<home>/external-agents.yaml`, bundled defaults (task runs write, investigate and review runs read-only, council member on), and the agy prerequisite with its daily latest-release check. The `/external-agents:antigravity` skill drives the `external-agents` command for agy the way `/external-agents:codex` does for Codex. Read-only runs use agy's default approval mode through a per-run settings file, so writes and commands are refused and reported as blocked; write runs use agy's auto mode, whose limit is agy's sandbox plus agy's own review. Every agy run passes `--disable-slash-commands`, so a prompt starting with `/` reaches the model as text, and a review warns when the branch changes agy's `.agents/` workspace configuration. agy runs are skipped until `antigravity.model` is set.
