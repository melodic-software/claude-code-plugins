---
bump: patch
---

### Changed

- The setup skill's eval suite moved from `skills/setup/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md`: eight `su-*` cases converted from the nine legacy cases, two of which share one case ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). `evals.json` is deleted; the suite cases now cover the four retirement records.

### Fixed

- The setup skill's `check` no longer says a missing `jq` makes every guard fail open: the blocking guards deny every Bash and PowerShell call, as the README says.
- The setup skill's `check` keeps a missing `node` at FAIL when every guard toggle is off, since no guard row starts without it.
