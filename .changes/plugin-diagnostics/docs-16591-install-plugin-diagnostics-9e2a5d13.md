---
bump: patch
---

### Fixed

- "On by default" applies to a new install only: a marketplace update does not install plugin-diagnostics where the marketplace was already installed ([ADR 0109, probe row `default-on-existing-users`](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0109-switch-plugin-sets-by-profile-and-gate-optional-calls-on-enabled-skills.md#probe-record-claude-code-21325-2026-11-15)). An existing install runs `claude plugin install plugin-diagnostics@melodic-software`. The README says the same.
