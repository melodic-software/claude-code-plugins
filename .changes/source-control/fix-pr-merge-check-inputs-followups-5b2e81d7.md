---
bump: patch
---

### Fixed

- The pr-merge gate no longer enqueues a stale-input pull request at its old head after an `update-branch` call that got no answer. A timeout, a failure with no HTTP status, or a server error may have landed the update, so the gate now holds with `check-inputs-changed` and records `updated: null` and the `updateError`; only a 4xx refusal enqueues as before.
- `merge.check-inputs` now reads only a full-history clone that is neither shallow nor partial. A blobless clone missing the base tip's `scripts/shared-copies.txt` read it as empty and answered `current` for a pull request it should have updated; it now answers `unknown`.
