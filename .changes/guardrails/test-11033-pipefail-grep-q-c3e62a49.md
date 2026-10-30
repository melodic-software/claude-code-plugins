---
bump: none
---

Test-only change: the tests match with a here-string or process substitution instead of piping into `grep -q`, so a match is not lost to SIGPIPE under pipefail. ([#11033](https://github.com/melodic-software/claude-code-plugins/issues/11033))
