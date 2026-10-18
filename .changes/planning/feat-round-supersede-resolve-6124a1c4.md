---
bump: minor
---

### Added

- `round.sh supersede` and `round.sh resolve` (#6124): terminal commands that set an answered register row of a ledger to `superseded-by-plan` (taking its resolution as `was`) and clear it by `reconfirm` or `restore`. They escape through the exporter, back the ledger up, print the `check-open-questions.sh` verdict, and need no page. `/planning:plan` "Plan changes after the Brief" names them instead of describing the grammar.
