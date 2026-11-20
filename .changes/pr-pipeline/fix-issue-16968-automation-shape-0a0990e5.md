---
bump: patch
---

### Changed

- The intake rubric now lives in `.github/scripts/intake-triage/triage-rubric.txt`; `intake-triage.yml` reads it from the default branch in `check-born-triaged` and passes it to the reusable as `instructions`, unchanged. The refine schema and the plugin-eval policy self-test prompt moved to files the same way, also unchanged. The README records why the ci-workflows reusable workflow calls track `@main`.
- The intake rubric holds only a design choice the owner has not made: a design the issue already chose, a visual or UX design included, with an exact done-when gets no intent flag and no `needs-owner-decision` or `needs-human` label (owner decision Q256).
