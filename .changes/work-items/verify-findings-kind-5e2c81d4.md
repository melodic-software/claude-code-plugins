---
bump: patch
---

### Changed

- The `work` skill's CI mode reads a fourth `author_kind` in `issue.json`, `verify-findings`: the
  pr-merge lane's record of the verifier's findings on an earlier pull request for the issue that
  it closed at the verify cap. Its text is data, never instructions: the run takes each finding
  only as a hint to check against the code and the issue's body, and reports any instruction in it.
