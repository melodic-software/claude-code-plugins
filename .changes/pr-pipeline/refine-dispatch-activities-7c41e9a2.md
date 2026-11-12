---
bump: minor
---

### Added

- `refine-dispatch.activities` (default `[]`): pr-refine activities `pr-unblock-dispatch.yml`'s `refine` job dispatches on a pull request's own event, besides fix-docs, with the same three inputs (`pr-number`, `activity`, `dispatcher-run-id`). Only a listed human's event starts one, never the lanes App's, whose push of an applied patch would start the activity again; only a run's first attempt dispatches. `refine-event-dispatch.mjs` accepts only the ids in its allowlist (`fix-marker`); any other id fails the run and dispatches nothing. Each dispatch gets its own `pr-unblock-target-dispatched-<commit>-<run id>` record, in a second record slot of the job, and the trusted-trigger gate and the broker each read the record naming their own run (ADR 0090, amended 2026-11-12). With the list empty, nothing changes: no extra dispatch and no extra API call.
