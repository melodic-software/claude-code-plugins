---
bump: patch
---

### Changed

- Split the shared page's browser suites into three parts, `tests/ui-a.test.sh`, `tests/ui-b.test.sh` and `tests/ui-c.test.sh`, in place of `tests/ui.test.sh`, so the test planner can put them on separate CI legs. `tests/ui-parts.txt` names each `ui_*.js` suite's part, and `tests/ui-run.sh` runs one part the way `ui.test.sh` ran them all: `UI_JOBS` at a time, slowest first, with `ui_snappy.js` and `ui_telemetry.js` alone at the end of part c. In CI, part c also runs alone on its leg, so other suites' browsers do not slow those two past their timing windows. A suite in no part or in two, or a part with no wrapper, fails every part before it runs anything. `bash tests/ui-run.sh --check` runs only that check.
