---
bump: patch
---

### Changed

- The `work` skill's CI mode reads a fourth `author_kind` in `issue.json`, `verify-findings`: the
  pr-merge lane's record of the verifier's findings on an earlier pull request for the issue that
  it closed at the verify cap. The run avoids repeating those failures and checks each finding
  against the code before acting on it.
