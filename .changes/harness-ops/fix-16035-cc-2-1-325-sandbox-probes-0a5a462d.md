---
bump: patch
---

### Fixed

- behavior-probes record 8 and its sandbox cases follow the Claude Code 2.1.325 change to sandboxed Bash, which now goes through the normal permission flow unless `sandbox.autoAllowBashIfSandboxed` is true: the two auto-mode cases set it, and a new default-mode pair measures the default itself (#16035).
