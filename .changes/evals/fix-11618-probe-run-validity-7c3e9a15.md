---
bump: patch
---

### Fixed

- `run-validity.py` no longer judges trigger-measurement runs INVALID. In a case tagged `invocation-probe` (written by `measure-invocation.sh emit-plugin-eval`), a should-trigger miss is reported as the measured rate, per case and overall, as a warning; and a max-turns run error in a run whose trace holds a Skill call is a warning, since the graded call already happened. Any other error, a max-turns error with no Skill call, and every non-probe case keep failing as before ([#11618](https://github.com/melodic-software/claude-code-plugins/issues/11618)).
