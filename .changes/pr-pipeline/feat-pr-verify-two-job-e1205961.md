---
bump: minor
---

### Changed

- pr-verify runs its model on the automations API key first and on the subscription token only after a key credit stop or when no key is set, as two jobs on run-claude-cli v0.54.0. A permission denial in either job yields no verdict.
