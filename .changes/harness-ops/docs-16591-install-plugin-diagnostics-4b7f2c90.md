---
bump: patch
---

### Fixed

- Upgrading from before 10.0.0, where the session hooks moved out of harness-ops: `plugin-diagnostics`, which now reports hooks that fail to launch, is on by default for a new install only. A marketplace update does not install it for an existing one ([ADR 0109, probe row `default-on-existing-users`](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0109-switch-plugin-sets-by-profile-and-gate-optional-calls-on-enabled-skills.md#probe-record-claude-code-21325-2026-11-15)), so run `claude plugin install plugin-diagnostics@melodic-software`. The README says the same.
