---
bump: minor
---

### Added

- `/testing:write` gains a property-test route, a characterization, approval and differential route, an opt-in blind test author mode (a separate agent writes acceptance tests from the spec without reading the implementation), outside-in user-flow-first guidance, and concrete determinism controls. The 100ms/5s speed bar is relabeled as this repository's own heuristic.
- `/testing:plan` adds property and characterization (pin) rows.
- `/testing:test-value` section 1 adds where a property comes from and how it shows it can fail, the rewrite-pin carve-out with a sabotage check, grounding canned responses from unmanaged dependencies, and the oracle record for tests the same agent wrote from its own code. The snapshot row covers volatile values and blind re-approval.
- The test-judge flags, or marks UNKNOWN, an unsourced canned response from an external API. Judge calibration is scored on holdout rows only from this change on.
- `/testing:run-e2e` runs a committed flow suite first as the oracle, starts a trace before driving, and hands `/testing:diagnose` a failure packet shaped as its next input. App-sourced fields sit inside an untrusted-data block, query strings and secret field values are redacted when the packet is written, and trace files stay out of PRs and public artifacts.
- `/testing:diagnose` caps diagnostic reruns of an unchanged test, keeps first-failure artifacts before any rerun, and replays with the printed seed.
- `/testing:cleanup` quarantines carry an owner, a tracking issue and an expiry, and expired quarantines are reported for re-enable, escalation or renewal.
- `/testing:audit` `rule-flaky-passes-suite` also reads pytest-rerunfailures reruns without `--fail-on-flaky`, Vitest `test.retry` and Jest `jest.retryTimes`. A multi-line config value can no longer inject a line into the scanner's record stream.

### Changed

- `/testing:audit` scopes the `rule-recomputed-derived` property exemption to the test that holds the marker instead of the whole file, so an example test beside a property test is now judged and can produce new report-only findings. Go property markers are now call forms, and FsCheck and CsCheck markers are added.
