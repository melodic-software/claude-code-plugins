---
bump: minor
---

### Added

- The deepening scan of `/architecture:improve` now looks for four hazards that mislead agents (split ownership, two ways to do one task, importable internals, hand-synced lists), each judged by an open-file test, and takes a spec or plan for upcoming work as its scope. The hazards and the open-file test follow pstack's `architect` design red flags.
- `/architecture:record-decision` offers a one-paragraph ADR shape and lists the kinds of decision that qualify, following Matt Pocock's `domain-modeling` ADR format.
