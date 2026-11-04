---
bump: patch
---

### Changed

- The setup skill's eval suite moved from `skills/setup/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md`: four `su-*` cases converted from the four legacy cases ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)).

### Fixed

- The setup skill's `check` now says that `context_guard_hooks_enabled` off also stops the module's toasts and crossing notice, not only its lines, as `plugin.json` already said.
