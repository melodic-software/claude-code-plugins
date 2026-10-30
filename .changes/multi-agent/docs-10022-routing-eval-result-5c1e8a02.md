---
bump: patch
---

### Changed

- **Routing eval result.** The routing rubric's evidence now records the paired routing eval over the worker, retrieval and verifier cases. Haiku 5.5 at `high` matched each role's current default on accuracy, but used more tokens per completed task in every role, so every default in `defaults.yaml` stands. The advisor arm could not run under `claude plugin eval` ([#10022](https://github.com/melodic-software/claude-code-plugins/issues/10022), part of [#6901](https://github.com/melodic-software/claude-code-plugins/issues/6901)).
