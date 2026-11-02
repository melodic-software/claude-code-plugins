---
bump: patch
---

### Changed

- The GitHub adapter of the work-item tracker wraps its `gh` calls with this repository's api-budget library when it runs in one of this repository's CI jobs, so each call's rate-limit reading reaches the job-end api-budget notice. Outside a CI job, and in an installed plugin where the library is absent, nothing changes.
