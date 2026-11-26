---
bump: patch
---

### Changed

- `/evals:plugin-eval` states its own rules (grant gated tools with `--allow-tools`, treat scores for hooks you did not write as advisory, read the CLI's message on an exit 1) and points at the plugin-evals docs sections for what a run loads, what a case cannot widen and what each exit code means, instead of restating them ([#19075](https://github.com/melodic-software/claude-code-plugins/issues/19075)).
