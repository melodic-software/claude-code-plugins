---
bump: minor
---

### Added

- `/work-items:work --ci` tidies its change before the review when the runner's prompt names tidy cutoffs: it measures the change (files, changed lines, areas, shared paths), and within the cutoffs invokes the named tidy entry with a lines file of its hunks and the tidy turn budget, then runs every check again. A change over a cutoff is not tidied, and `tidy` is recorded in `steps` either way; tidy never fails the run.
