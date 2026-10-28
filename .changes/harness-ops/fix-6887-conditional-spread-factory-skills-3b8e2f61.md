---
bump: patch
---

### Fixed

- **The inventory reads built-in plugin skills past a conditional spread.** A skill factory whose returned object holds `...COND&&{...}` (Claude Code 2.1.296's claude-test plugin) no longer drops every key written before it: the spread shadows only its own keys, which read as unresolved. On 2.1.296 the claude-test skills' descriptions and `user_invocable` now resolve, and only its `gate_flags`, an accepted floor, stays partial.
