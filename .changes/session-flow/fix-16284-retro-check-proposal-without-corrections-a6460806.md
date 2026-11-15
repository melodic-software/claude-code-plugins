---
bump: patch
---

### Fixed

- `/session-flow:retro`: the gotcha on mechanical findings puts "when the `corrections` plugin is
  installed" on the hand-off to `/corrections:codify`, where the condition applies.
- `/session-flow:retro`: without the `corrections` plugin, the catalog's "Check first" step states
  in item 2 that one occurrence of a policy-class mistake is enough to propose a check, beside a
  repeat with the same cause.

### Added

- An eval case for a retro with no `corrections` plugin: one force-push to main gets a
  Hooks-format check row naming its ladder rung and the requirements the check must still meet,
  and no prose line.
