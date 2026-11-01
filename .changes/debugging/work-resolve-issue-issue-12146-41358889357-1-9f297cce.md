---
bump: minor
---

### Added

- `/debugging:debug` Phase 6 now searches the codebase for the same defect shape once the cause is fixed, and fixes each sibling in the change or files it, naming the search and each sibling in the record. One cause usually has more than one instance. Adapted from the `fix-root-causes` principle in the pstack collection of [cursor/plugins](https://github.com/cursor/plugins).
- Phase 6's record now proposes one cheap, always-on signal (a log line, a metric or an assertion) that would have shown the deciding fact at first look. The new `always_on_signal` key in a repository's `docs/conventions/debugging.yaml` gates it: `when-instrumented` (the default) proposes one when Phase 4 instrumentation ran, `always` on every run, `never` not at all. The plugin ships `schemas/debugging.schema.json` for the file. Adapted from the same principle.
- Eval case `phase6-finds-sibling-and-proposes-signal`: a fixed lookup defect with a second copy in another file and a Phase 4 instrumentation step, graded on naming the second instance and proposing an always-on signal.

### Changed

- The bundled phase checklist's Phase 6 line now names the sibling search and the always-on signal proposal, and Phase 5's diff rule lets the fix commit carry sibling fixes of the same cause with their regression tests.

- The "Does not fix the symptom" line keeps its null-check example and now states the test, adapted from the same principle: handling a state is the fix when the system can legitimately be in it, and a guard hides the bug when the state should never exist.
