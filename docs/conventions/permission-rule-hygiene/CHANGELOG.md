# Permission Rule Hygiene Convention — Changelog

Notable changes to the permission-rule-hygiene convention. The convention states a principle and three
anti-patterns; it is enforced by the `claude-config` plugin's `permission-hygiene` skill (checks
P1/P2/P3), whose detector and criteria version independently of this document.

## 1.0 — 2026-07-14

Initial published convention.

- Principle: the operative allow-rule for a guarded code-execution helper must be a narrow,
  machine-independent, bare-command rule the operator adds to user-global settings.
- Anti-pattern 1 — interpreter-wildcard / blanket allow rules dropped in auto mode.
- Anti-pattern 2 — hardcoded absolute machine/user paths (Bash rules match literally, no expansion).
- Anti-pattern 3 — assuming a skill or plugin can self-grant an auto-mode-gated action class.
- Correct pattern: bare command on the Bash tool PATH (pre-plugin PATH shim, post-migration plugin
  `bin/`) allowed narrowly by bare name, with an operator-setup boundary note.
