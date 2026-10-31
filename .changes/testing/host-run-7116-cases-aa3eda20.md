---
bump: patch
---

### Fixed

- The `run-e2e-app-control-absent-reports-drift`, `run-e2e-flat-feature-id-resolves` and
  `run-e2e-grouped-feature-id-resolves` eval cases now expect what `/testing:run-e2e` does without
  app-control: `touched features not matched (app-control not installed)`, no refresh, and a next
  step of installing app-control. The flat and grouped cases check the feature id on the report
  lines.
