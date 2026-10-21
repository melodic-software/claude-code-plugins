---
bump: minor
---

### Added

- **Dispatch briefs carry the Brief.** A new brief item quotes PLAN.md's Problem, Goal (with the Intent, Vision and conflict-preference lines), Out-of-scope and the load-bearing assumptions the phase depends on.
- **Worker discoveries.** Implementer reports gain a `discoveries:` field for stale dependencies, better options and assumption checks; the orchestrator records every non-STOP problem, open question and discovery.

### Changed

- The divergence ladder keeps Minor, Moderate and Major and defines them as proceed and note, flag and continue (a better option is logged, never adopted unasked), and stop and replan. Brief item 2 is the divergence clause's only owner and finishes in-fence work before reporting.
- Step 3.5 records an invented item as a `human-decision` entry when nobody can answer, grades a worker discovery on the Step 3 ladder instead of its own table, and completion fold-back writes dated pivot notes into PLAN.md.
