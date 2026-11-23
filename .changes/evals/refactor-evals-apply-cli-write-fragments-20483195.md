---
bump: patch
---

### Added

- **`apply_step`, `plugin_cli_write` and `plugin_cli_write_with_help` grader fragments.** The shared matchers now hold the git-hooks apply-step command and the `claude plugin` write command, each in its own file with must-pass and must-fail samples, and every `no-apply-step` and `no-plugin-cli-write` grader in this repository builds from them instead of carrying its own copy.
