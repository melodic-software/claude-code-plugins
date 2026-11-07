---
bump: patch
---

### Changed

- The audit, principles and setup `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). 43 new cases cover every legacy case; `au-dirty-target-stops` gains a grader for the one it already covered.
  - The exercised-scope cases load an eval-only `testing` stand-in that answers the test-file check.
  - The skill-level fixtures become seed scripts under `evals/fixtures/`.
