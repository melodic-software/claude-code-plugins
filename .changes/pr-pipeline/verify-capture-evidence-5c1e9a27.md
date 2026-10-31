---
bump: minor
---

### Added

- `merge.verify-capture` configures pr-verify's evidence capture: `app`, the app it drives (unset: no capture runs), and `retention-days` (default 30, at most 90) for each capture artifact.
- Every verdict file records an `evidence` block: the capture's outcome (`no-app` when no capture summary exists, `blocked` when one cannot be read) with its reason, capture count and features, and `local_loop`, the author's count from an `Evidence loop: k/3` line in the trusted pull request body, read as data and `null` without one. A capture never fails the verdict.
