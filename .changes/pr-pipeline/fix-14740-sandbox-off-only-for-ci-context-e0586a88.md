---
bump: patch
---

### Security

- The read runner's `run-claude-cli` legs turn Claude Code's sandbox off only for a `prepare: ci-context` skill, whose bare Bash may reach hosts beyond GitHub. Every other read activity runs its Bash in run-claude-cli's default sandbox.
