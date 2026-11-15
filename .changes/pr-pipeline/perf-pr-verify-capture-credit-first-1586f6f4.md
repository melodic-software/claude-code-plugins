---
bump: patch
---

### Changed

- The Verifier verdict section says the capture job reads the key's credit history before its resolver, and while the credit gate skips the key it stops there and uploads no capture, so the verdict records the capture `blocked` with the reason "left no capture artifact for this head". The match step now runs before the key call, after the credit read.
