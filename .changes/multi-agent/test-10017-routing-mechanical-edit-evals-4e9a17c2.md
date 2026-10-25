---
bump: patch
---

### Added

- Three mechanical-edit cases for the model-routing eval under `evals/routing/mechanical-edit/`: a rename scoped to one file, a link repoint after a file move, and a table-to-list format change. Each case builds its workspace from `scaffold.sh` and is graded only by deterministic regexes over the workspace files. `arms.yaml` sets out the eight model and effort arms the cases run under ([#10017](https://github.com/melodic-software/claude-code-plugins/issues/10017), part of [#6901](https://github.com/melodic-software/claude-code-plugins/issues/6901)).
