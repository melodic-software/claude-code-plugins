---
bump: patch
---

### Fixed

- The unattended merge gate reads `merge.max-in-flight` at the default branch head, once per cache window shared by the run's gate processes and again uncached after an enqueue, instead of at each pull request's base, so a pull request whose base predates a cap change no longer runs at the old cap. When the head's config cannot be read, the base's value applies, and the room check after an enqueue keeps the lower of that and the cap the gate applied. The gate report's `inFlight` names the cap and where it was read.
