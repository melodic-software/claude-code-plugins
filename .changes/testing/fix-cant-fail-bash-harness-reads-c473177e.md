---
bump: patch
---

### Fixed

- **audit:** the can't-fail scan reads more bash-harness assertion shapes. A `[[ ]]` test followed by a bare `exit`, which returns its status, is no longer reported as `rule-inert-assertion`. An `exec` of `bash`, `sh`, `node`, a Python, `pwsh` or a variable command counts as delegation, and a failure counter or `rc=` accumulator the script exits on (`exit "$fails"`, `exit "$rc"`, or an `if ((fails > 0))` or node `if (failed)` guard before `exit 1` or `process.exit(1)`) counts as an assertion, so a test built on its own `check()` helper is no longer reported as `rule-zero-assertion`. On this repository the whole-tree scan drops from 3 inert-assertion flags to 0 and from 33 zero-assertion flags to 1. New corpus pairs pin each shape, good and bad.
