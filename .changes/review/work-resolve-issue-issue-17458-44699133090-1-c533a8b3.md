---
bump: patch
---

### Changed

- The loosened-check summary line in a review now reads `Loosened checks would be marked: <value> (<layers>); patterns: <count>` in place of `Loosened-check verdict: ...`. The line states the policy in force, so a review that finds no loosening no longer shows `verdict: fail`, which read as a failed check. The `loosened_check_verdict` setting, its values and the settings resolver's output keys are unchanged.
