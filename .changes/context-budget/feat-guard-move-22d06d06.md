---
bump: major
---

### Removed

- The settings-write ask hook and its `settings_write_ask_enabled` option leave context-budget for the guardrails plugin, which runs the same checkpoint. Enable guardrails to keep it, and set `settings_write_ask_enabled` again there if you had changed it: the value set here does not carry over.
- `/context-budget:setup` no longer reports the toggle or prints a route to change it, and its `node` check names only the measurement engine. The setup evals that tested the toggle are removed, and the rest no longer name it.

### Changed

- `/context-budget:audit fix` names the guardrails checkpoint, when guardrails is enabled, as what makes a project settings edit prompt.
