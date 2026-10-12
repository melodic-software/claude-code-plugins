---
bump: patch
---

### Changed

- `/skill-quality:check`, `/skill-quality:setup`, the README, the invocation-probes reference and the two checker scripts now point at the exact upstream docs sections, each with an as-of date and a recheck trigger, instead of restating the listing caps, budget defaults, plugin cache layout, plugin eval case shape, `pluginConfigs` scopes and `claude plugin install --config` behavior. The listing-cap constant has one record, in `check-skill.sh`.

### Fixed

- The `check-skill.sh` comment on unresolved `plugin:skill` names no longer says the plugin cache's version nesting is undocumented; the plugin loading reference now documents it.
