---
bump: minor
---

### Changed

- **audit:** `rule-inert-assertion` now gates `--check`, `--strict` or not, the same way `rule-zero-assertion` does. A whole-repository precision run traced every flag to one scanner misread, fixed since, and the rerun flags nothing. `--check` exits 1 on it, the `Ran:` line counts it with the gating rules, and the report-only note no longer lists it. The other six report-only rules are unchanged.

### Fixed

- **audit:** the can't-fail scan reads a bash-harness test that runs `bash`, `sh`, `node`, a Python, `pwsh` or a variable command and then exits with `exit $?` as delegation, the way it reads `exec`, so such a test is no longer reported as `rule-zero-assertion`. The command must start its line or follow `;`, `&` or `|`, so a quoted variable in argument position (`echo "$out"`, `cp "$a" "$b"`) before `exit $?` is still reported, as is the same command followed by `exit 0`. New corpus fixtures pin each case.
