---
bump: patch
---

### Fixed

- `plugin-eval`'s `run-validity.py` has a `scaffold` check: a case whose `case.yaml` sets `context.scaffold_script` fails the run unless `--scaffolded` records that the eval ran with `--scaffold`, because without it both arms ran in an empty workspace and the result still read VALID. A `case.yaml` it cannot locate or read leaves the check UNCHECKED ([#10504](https://github.com/melodic-software/claude-code-plugins/issues/10504)).
