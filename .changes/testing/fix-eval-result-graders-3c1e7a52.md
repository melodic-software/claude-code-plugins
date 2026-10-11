---
bump: patch
---

### Fixed

- evals: the `cli-resolves` (browser-probe) and `echo-printed` (sandbox-probe) graders now match a Bash `tool_result` whose content starts with the expected output and may carry stderr after a newline, the way Claude Code joins stdout and stderr, instead of requiring the output to be the whole content; Claude's own text naming the value no longer passes.
