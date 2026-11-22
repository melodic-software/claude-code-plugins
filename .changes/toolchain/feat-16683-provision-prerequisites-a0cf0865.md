---
bump: patch
---

### Changed

- A `skip (prerequisite missing: <name>)` cell for an entry with an `install` object names the provisioning step that installs it, the source-control plugin's `provision-prerequisites.sh`. The check still installs nothing. A test fails if the not-run rules in `check`, its gates and `lint` stop naming that step.
