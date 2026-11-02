---
bump: patch
---

### Fixed

- **evals:** six outcome-suite graders no longer pass a run that did the wrong thing. `engines-corrected` and `test-runner-corrected` fail a reply that quotes package.json but keeps `node >=16` or jest. `advancing-reply-literal` no longer takes a command to type into a terminal as the reply. `added-count-3` no longer reads a `3.` list number as the count. `skips-unrelated-standard` fails a Grep that returns `frontend-css.md` content. `swallow-removed` fails a bare or `Exception` catch. A new `deprecated-flag-removed` grader fails a run that leaves `importsNotUsedAsValues` in tsconfig.json. Each change has a must-fail sample.
