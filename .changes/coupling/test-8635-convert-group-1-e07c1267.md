---
bump: patch
---

### Changed

- The eval suite moved from `skills/*/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md`, with deterministic graders where an expectation is mechanical and a scaffold repository for each case whose prompt describes files ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
