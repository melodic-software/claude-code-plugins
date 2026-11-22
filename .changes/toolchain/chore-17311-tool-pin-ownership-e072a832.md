---
bump: patch
---

### Changed

- `/toolchain:lint` says a record sets `tool-pin` only for a tool whose version the repository owns itself, and omits it when the version comes from a shared default such as a composite action's input default, since a copy drifts.
