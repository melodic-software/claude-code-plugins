---
bump: patch
---


### Changed

- implement asks whether a finished block could be fewer lines

  The execution cadence gains a fewer-lines check in every mode: before the
  commit checkpoint, a block that can say the same thing in fewer lines with
  identical behavior is shrunk. It applies to the result `integration_posture`
  calls for.
