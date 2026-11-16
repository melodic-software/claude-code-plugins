---
bump: patch
---

### Fixed

- `/session-flow:retro`: without the `corrections` plugin, the catalog's Hooks recommendation format
  asks a check row for its ladder rung id and the guardrail criterion items left open as
  requirements, and "Check first" lists item 6 as open only when the rung runs in more than one
  place, as the enforcement ladder says.
- `/session-flow:retro`: a finding that gets a check row gets no CLAUDE.md, `AGENTS.md` or
  rules-file line in any form, a fallback for a withheld or declined check included, and Phase 4
  offers none; the Hooks format names the open criterion items one by one, and its check row always
  states the hook's four fields, a deny rule only beside the hook.
