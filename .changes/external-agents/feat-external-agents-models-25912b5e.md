---
bump: minor
---

### Added

- `external-agents models <product>` prints the installed CLI's models and effort levels as one JSON document (schema 1), naming the command each fact came from, for other plugins such as `/multi-agent:route` to read instead of this plugin's cache files. It caches per CLI version and starts no model turn; a missing CLI is `unavailable` with exit 4.

### Changed

- `external-agents update codex` also caches `codex debug models`, and reports `check: cli facts` when it fails. The model list no longer joins the help text `update` searches for config keys.
