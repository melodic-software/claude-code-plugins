---
bump: patch
---

### Fixed

- **measure-invocation:** the emitted README and the reference example put live cases under `probe-evals/<plugin>`, which git ignores, instead of `.work/`, which `claude plugin eval --eval-dir` refuses.
