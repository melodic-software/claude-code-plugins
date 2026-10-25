---
bump: patch
---

### Fixed

- **`/testing:check-visual-parity` route 1 says how to run the suite and what a run with no verdict means.** It runs the repository's visual suite through the repository's own entry point (its documented test command or runner script) and names that command in the report. A state the run did not compare (a build, install or browser-launch error, or no baseline image) has no verdict: the environment failure is reported with its last lines, and the state takes the gap report and never moves to another route. A new eval case covers a suite run that fails before comparing ([#10105](https://github.com/melodic-software/claude-code-plugins/issues/10105)).
