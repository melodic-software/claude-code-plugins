---
bump: patch
---

### Changed

- The produce skill's eval suite moved from `skills/produce/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md`: six legacy cases became eight `pr-*` cases that grade the run's decisions without needing a render to succeed, and the missing-tool case is covered by `ck-notice-runs-own-report` ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). `evals.json` is deleted.
