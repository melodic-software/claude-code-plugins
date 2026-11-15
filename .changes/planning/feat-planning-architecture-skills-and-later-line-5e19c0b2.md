---
bump: minor
---

### Added

- **`/planning:design` uses the architecture skills when the work changes module structure.**
  Phase 4 invokes `/architecture:principles` (if enabled) for the module-design terms the topology
  uses, and names `/architecture:improve` (if enabled) as the step that finds which existing
  modules to reshape. Without the architecture plugin it says once what the plugin would add.
- **`/planning:plan`** names both skills in its prerequisite check when the plan reshapes existing
  modules.
- **`/planning:interview` round header gains a `Later:` line** naming the topics of rounds already
  known to follow, so the user sees what is coming without being asked it yet.
