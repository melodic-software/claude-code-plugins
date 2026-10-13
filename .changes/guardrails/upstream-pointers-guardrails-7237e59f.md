---
bump: patch
---

### Changed

- Hook comments in `run-guards.sh`, `abort-boundary.sh`, `block-hook-bypass.sh`, `block-dangerous-git.sh`, `flag-commit-pr-skill-bypass.sh`, `skill-reference-verify.sh` and `stale-path-verify.sh`, and the edit-write-guards plan, no longer restate Claude Code hook, Edit tool, settings-precedence and plugin-manifest behavior. Each states the guard's own reasoning and carries a pointer record (section anchor, as-of date, recheck trigger); `stale-path-verify.sh` cites the Edit-tool record in `skill-reference-verify.sh`. No guard logic changed.
