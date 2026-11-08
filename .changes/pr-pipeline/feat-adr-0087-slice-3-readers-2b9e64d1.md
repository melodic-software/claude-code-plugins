---
bump: patch
---

### Changed

- A pipeline check run carries the lane-outcome record alone: `report-check-run` no longer writes the `lane=<lane> activity=<activity> class=...` first line of `output.summary` or its JSON block in `output.text`, and its `lane-class`, `lane-resets`, `lane-turns`, `lane-max-turns`, `lane-models` and `lane-profile` inputs are removed. The pr-unblock dispatchers read a limit stop only from the record. A read leg that fails before the launcher names its credential (a CLI install) records the secret its call was given, so its record is still written.
