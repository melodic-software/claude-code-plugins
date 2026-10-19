---
bump: patch
---

### Fixed

- `/source-control:pull-request ready` no longer flips right after a push: it waits up to 90 seconds for the push's CI run on the new head, so the draft-payload `synchronize` run cannot cancel the `ready_for_review` run and leave `ci-status` red. After the flip it confirms a new CI run exists for the head and, when none appears within 120 seconds, toggles draft and ready once and names the toggle in its report.
