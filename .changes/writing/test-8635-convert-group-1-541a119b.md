---
bump: patch
---

### Changed

- The eval suite moved from `skills/*/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md`, with deterministic graders where an expectation is mechanical ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
- Its fixtures moved to `evals/fixtures/`, copied into the workspace by each case's scaffold.
