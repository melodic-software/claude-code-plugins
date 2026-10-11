---
bump: patch
---

### Fixed

- evals: the `cli-resolves` (browser-probe) and `echo-printed` (sandbox-probe) graders now match the expected output at the start of any line of a Bash `tool_result`, so the `.bashrc: Permission denied` lines the eval sandbox prints first no longer hide it; a result that begins with `Exit code` (a failed call) still does not match.
