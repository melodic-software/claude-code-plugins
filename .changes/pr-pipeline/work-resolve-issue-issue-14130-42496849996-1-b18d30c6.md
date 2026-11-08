---
bump: patch
---

### Fixed

- Intake triage reads a verdict's `Size:`, `Complexity:` and `Uncertainty:` values in any case, so `small` and `Small` both name the `small` option of `models.issue-dimensions`. Its field write sends the lowercase option name and, when GitHub answers 400 or 422, sends the Title-case name once more; either way it checks the answer by option id. Renaming the org's Size, Complexity and Uncertainty options to lowercase (ids unchanged) no longer breaks the write.
