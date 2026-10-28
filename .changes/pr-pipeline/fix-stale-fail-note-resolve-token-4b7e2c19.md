---
bump: patch
---

### Fixed

- A pass-only address-feedback round no longer stops the lane and turns ci-status red when GitHub refuses to resolve a stale pr-verify fail-note thread. The lanes App token (`contents: read`) resolves a thread only on a pull request the App opened, so on a pull request a person opened every resolve failed with `Resource not accessible by integration`, the reply job failed, and the run posted a `pr-unblock/address-feedback` failure (`feedback-publish-failed`). `publish-feedback.mjs` now logs a warning naming the threads it could not resolve and skips `pass-only` as before; the open threads still block the merge under required thread resolution. No job's permissions change.
