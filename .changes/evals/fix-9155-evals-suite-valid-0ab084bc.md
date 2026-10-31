---
bump: patch
---

### Fixed

- `plugin-eval` no longer says a target after `--json` is swallowed: on current Claude Code `--json` takes an optional path. A target after `--tag` or `--allow-tools` still is, and the CLI then loads every suite under the working directory; the `target-before-json` case now tests that.
- `plugin-eval` records that with-arm reads under a plugin directory named `evals` are denied while the same copy under another name reads its spokes, and tells a run to copy such a plugin under another name.
- The `va-unknown-timeout-key` case no longer grants Bash, so no case in the suite needs it.
