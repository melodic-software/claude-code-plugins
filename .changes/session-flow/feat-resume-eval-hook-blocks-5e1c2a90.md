---
bump: minor
---

### Added

- The resume-eval grader records a reader refused by a plugin's PreToolUse hook (such as guardrails' `block-cd-prefix.sh`) as `hook-blocked`, named by the hook's plugin, event and refusal line, instead of a plain denial. The report counts hook-blocked runs, and runs in which a hook refused any call, per arm and per pair, apart from accuracy and the non-delivery rate.
