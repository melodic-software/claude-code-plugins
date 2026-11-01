---
bump: patch
---

### Fixed

- `audit`: persisting findings no longer searches the host filesystem for the `review` plugin. Installed-ness comes from the session's skill listing and the plugin's directory from a loaded `review` skill; otherwise the run falls through to the publisher URL.

### Added

- Outcome eval cases for `audit` and `setup`, and a frozen trigger-probe file for `audit`.
