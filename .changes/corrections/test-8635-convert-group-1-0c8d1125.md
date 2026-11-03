---
bump: patch
---

### Changed

- The eval suite moved from `skills/*/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md`, with deterministic graders where an expectation is mechanical ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).
- `codify-person-note-appends-row-from-file` scores `runs-buffer-append` in the with-plugin arm only, because the no-plugin baseline cannot call the plugin's bundled `buffer.sh`.
