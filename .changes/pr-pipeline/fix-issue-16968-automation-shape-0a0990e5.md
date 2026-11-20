---
bump: patch
---

### Changed

- The intake rubric now lives in `.github/scripts/intake-triage/triage-rubric.txt`; `intake-triage.yml` reads it from the default branch in `check-born-triaged` and passes it to the reusable as `instructions`, unchanged. The refine schema and the plugin-eval policy self-test prompt moved to files the same way, also unchanged. The README records why the ci-workflows reusable workflow calls track `@main`.
