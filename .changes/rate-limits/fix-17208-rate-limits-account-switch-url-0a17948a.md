---
bump: minor
---

### Added

- `account_switch_url` names the link the options line gives for switching accounts. Unset, the line says the user can switch accounts with no link; the plugin no longer ships a link to one organization's account-rotation repository. A value that is not one http(s) URL reads as unset, with one transcript line naming it.

### Changed

- The reader contract's drain-then-pause bullet names the `account_switch_url` option in place of that link.
