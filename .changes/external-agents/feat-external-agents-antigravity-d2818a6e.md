---
bump: minor
---

### Added

- Google Antigravity (`agy`) support: a provider record, the `antigravity` keys in `<home>/external-agents.yaml`, and bundled defaults (task runs write, investigate and review runs read-only, council member on). Read-only runs use agy's default approval mode through a per-run settings file, so writes and commands are refused and reported as blocked.
