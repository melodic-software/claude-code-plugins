---
bump: patch
---

### Changed

- read provenance: untrusted as the untrusted-provenance label

  Triage now applies `provenance: untrusted` to a signal-marked item in
  place of `work-class: untrusted-provenance`. The autonomous frontier,
  the work-loop provenance and provenance-removal holds, the attend-queue
  flip rules and the triage pairing ban and sweep hold both names: the
  legacy one stays floored until the label source drops it.
