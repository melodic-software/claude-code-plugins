---
bump: minor
---

### Changed

- **`setup` names what the detected test runner supports up front.** `apply` step 2 says, beside
  the tool proposal and before the diff-target question, whether the runner supports
  `audit --exercised` and `/testing:cleanup`'s mutation gate; a name-filter-only runner (Maven
  `-Dtest`, Gradle `--tests`) supports neither, so the user can stop before investing in setup.
  `check` step 3 adds the same line as an INFO row. A new setup eval case covers a Gradle project.
