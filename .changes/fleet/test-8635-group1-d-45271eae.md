---
bump: patch
---

### Changed

- The eval suite moved from `skills/*/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md`, with deterministic graders where an expectation is mechanical ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Three legacy scenarios that the `fr-*` outcome cases already cover are dropped, and each kept prompt names the workspace fleet manifest.
