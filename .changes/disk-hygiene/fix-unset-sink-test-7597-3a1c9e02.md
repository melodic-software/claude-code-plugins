---
bump: patch
---

### Fixed

- The unset-sink telemetry test now asserts that no sink process is launched, so it fails if the emitter stops treating an unset sink as a no-op.
