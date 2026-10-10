---
bump: minor
---

### Added

- **`/evals:design` case authoring keeps cases looking like real work, and `/evals:plugin-eval` ends its delta reading with a verdict.** A case prompt states what the user wants done and never that it is a test or what it checks; prompts, fixture paths and slugs carry no evaluation words; and no expectation is graded from the model's own account of what it did. Reading the delta now spot-reads outputs from both arms against their verdicts before trusting the number, and ends with one `promote` or `do not promote` line naming the first condition that failed.
