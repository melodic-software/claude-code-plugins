---
bump: patch
---

### Changed

- The setup skill's eval suite moved from `skills/setup/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md`: eight `su-*` cases with scaffolded repositories, converted from the eight legacy cases ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).

### Fixed

- `setup` `check` probes the linter with `--help` instead of `--version`, so a liveness check runs no repository code under a config awaiting approval. The tool counts as executing when the first output line is its version banner, whatever the exit code.
