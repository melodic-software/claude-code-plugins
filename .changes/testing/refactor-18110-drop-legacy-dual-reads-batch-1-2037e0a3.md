---
bump: major
---

### Removed

- Stop reading retired `~/.claude/testing.yaml`, `.claude/testing.yaml`, `.claude/testing.local.yaml`, `~/.claude/testing/e2e.md`, `.claude/testing/e2e.md`, `.claude/testing/e2e.local.md`, and `.claude/testing/worst-case.md` files across `resolve-config.sh`, `visual-compare.sh`, `cant-fail-scan.sh`, `judge-lib.sh`, and `run-e2e`, and remove `/testing:setup` `--copy-old` and the `.claude/testing.yaml` write fallback.
