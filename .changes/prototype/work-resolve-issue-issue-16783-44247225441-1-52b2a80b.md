---
bump: minor
---

### Changed

- The control panel no longer names a default panel library for React projects. It resolves the
  panel library from the repository through the plugin's new copy of the ecosystem resolution
  steps (`reference/ecosystem-resolution.md`, version 1.1.0), and uses plain range inputs when
  none resolves.
- The control panel's rule that controls write CSS variables on the prototype root no longer
  carries framework-specific code examples.
- `/prototype:pressure-test` no longer shows package-manager or SDK commands as examples of the
  one start command; it asks for one short command through the project's task runner.
