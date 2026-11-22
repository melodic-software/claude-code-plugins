---
bump: minor
---

### Added

- `run` and `review` take `--effort <level>` to override `<product>.effort` for one run; agy receives `--effort` and Codex receives `-c model_reasoning_effort=<level>`. Each job records the model and effort it ran with, and `status <job>` prints them.

### Changed

- The `antigravity` and `codex` skills still pass no model or effort by default, so each vendor's shipped default runs; the calling agent may pass `--model` or `--effort` for one run when the user names one or a heavy whole-task delegation calls for it, and names the override in its reply.
