---
bump: minor
---

### Added

- `scripts/repin-digests.sh` re-pins the digest pins of `tests/interview-defenses.test.sh` from
  the files alone. It takes the same arguments as `tests/repin.sh`, reads the test file as text,
  and computes each pin's digest itself. It runs neither the test nor any other file from the
  checkout. A pin argument that is not a plain quoted string, or that names a file outside the
  plugin, refuses the pin and leaves the file unchanged. The issue lane can run it, so a lane
  change to a pinned interview section no longer stops for a host session to re-pin.

### Changed

- The digest computations move to `scripts/lib/pin-digests.sh`, which the test and
  `repin-digests.sh` both source, so a re-pin computes each digest the same way the test grades
  it. `tests/repin.sh` now calls `repin-digests.sh` and then runs the test, and keeps its exit
  codes.
