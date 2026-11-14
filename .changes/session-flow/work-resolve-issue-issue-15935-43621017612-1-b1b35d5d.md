---
bump: minor
---

### Changed

- The `retro` improvement catalog now asks of each finding, before the scope question, whether a check could decide it. When one can, the recommendation is a check proposal handed to `/corrections:codify` when that plugin is installed, or else written in the Hooks format against the retro's enforcement-ladder copy, and the finding gets no `CLAUDE.md` or rules-file line. Session mode's Phase 3 runs this step before it chooses a target.
- The catalog's target sections now run strongest first: Hooks and Settings, then CLAUDE.md / Rules, then Memory. The CLAUDE.md / Rules section opens with its condition: no rung above guidance can decide the finding.
- The catalog's "When to propose a check" no longer keeps its own recurrence count. It points at `/corrections:codify`'s `recurrence.min_occurrences` setting, keeps one occurrence for a policy-class mistake, and falls back to a repeat with the same cause when the `corrections` plugin is not installed.

### Added

- The `re-mechanical-finding-check-proposal` eval: a mistake made twice in one session that a lint rule could catch (importing a banned library) must come back from a session retro as a check routed to `/corrections:codify`, with no prose rule proposed for it.
