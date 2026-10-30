---
bump: none
---

Test-only change: the test matches with process substitution instead of piping into `grep -qE`, so a match is not lost to SIGPIPE under pipefail. ([#11033](https://github.com/melodic-software/claude-code-plugins/issues/11033))
