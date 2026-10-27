---
bump: minor
---

### Added

- `/machine-health:setup apply` takes `exclude-service=<name>` and `include-service=<name>`: `Set-ApprovalState` gains the `exclude-service` and `include-service` actions, which add a name to `approvals.json` `check_overrides.services.service_exclusions` (one already listed in any case is skipped) and remove it in any case, under `approvals.lock`, checked against the schema and replaced atomically like mutes and approvals. A blank name, one over 256 characters, one with leading or trailing whitespace, or one holding `/`, `\` or a control character is refused and nothing is written; including a name that is not listed throws.

### Changed

- `service_exclusions` is no longer the one key the owner edits by hand: the `approvals.json` schema description and `approvals.md` now say setup writes it.
