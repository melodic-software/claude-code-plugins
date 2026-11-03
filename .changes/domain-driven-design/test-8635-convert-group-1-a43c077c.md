---
bump: patch
---

### Changed

- The eval suite moved from `skills/*/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md`, with deterministic graders where an expectation is mechanical ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
- Its fixtures moved to `evals/fixtures/`, staged by each case's scaffold under `docs/language/`.
- `/domain-driven-design:curate-language` records a name the resolution rules out ("never the X") as a rejected synonym in the file's convention, not inside the definition.
