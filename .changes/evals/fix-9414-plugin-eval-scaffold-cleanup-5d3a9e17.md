---
bump: patch
---

### Fixed

- `plugin-eval` preflight's leftover-sandbox cleanup now prints a per-sandbox loop that opens each sandbox and its mode-000 `sealed/` directory with `chmod 700` before `chmod -R u+rwx` and `rm -rf`, since the old `chmod -R u+w` stopped with `Permission denied` on a kept sandbox ([#9414](https://github.com/melodic-software/claude-code-plugins/issues/9414)).
- `plugin-eval`'s run step now adds `--scaffold` when a selected case's `case.yaml` sets `context.scaffold_script`, after the user reads each such script, because such a case run without it runs against an unstaged workspace and its delta reads 0 ([#9414](https://github.com/melodic-software/claude-code-plugins/issues/9414)).
