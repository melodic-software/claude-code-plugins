---
bump: minor
---

### Added

- The babysit merge gate takes `--unattended`, the entry point of the unattended merge path. Its policy is inert: check-only reports the blocker `unattended merge inert: authority-unconfigured` and `unattended.enabled: false`, `--merge --unattended` refuses at exit 10 before any network call, and the flag refuses `--allow-dependency` and `--auto`. Without the flag the gate is unchanged.

### Security

- Plain `--merge` on the babysit merge gate refuses at exit 10 when the token's acting login is the configured `merge.agent-identity`, or cannot be read while one is configured, so the agent identity can merge only through `--unattended`.
