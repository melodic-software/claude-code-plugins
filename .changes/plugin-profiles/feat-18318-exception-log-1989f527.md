---
bump: minor
---

### Added

- Each `start --resume <id> --profile-add <plugin>` reopen records one exception per requested plugin in this machine's `exceptions.jsonl` in the plugin's data folder (never on `--dry-run` or a refused reopen); records older than 30 days are pruned.
- When one profile has been reopened with the same plugin in three distinct conversations since that pair was last reviewed, the session-start notice suggests `/plugin-profiles:profile setup`.
- `exceptions [--json]` lists each profile and plugin pair with its count since its last review, and `exceptions --reviewed <profile> --plugin <id>` records a review. Profile setup now starts with a review step that reads the log and asks per pair whether to add the plugin to the profile or keep it off.

### Changed

- `save --plugins` and `--optional` drop the ids they add from that file's `remove` and `exclude` lists, and the preview says `Stays off` when another file of the profile still switches one off.
