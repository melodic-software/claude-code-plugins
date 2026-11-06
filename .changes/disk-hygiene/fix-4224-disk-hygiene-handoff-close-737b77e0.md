---
bump: patch
---

### Changed

- **On Linux, the `apply` prompt is the tier's only removal question** ([#4224](https://github.com/melodic-software/claude-code-plugins/issues/4224)). The skill asked a separate approval question after preview and then the guard's hook `ask` on `apply` asked again, though that prompt already lists the tier, the count and every path. The skill now shows the tier's table and runs `apply`, whose hook `ask` is the confirmation gate's removal question, as `handoff-apply`'s already is on Windows. Where a hook `ask` would not prompt in the session's mode, the skill still asks the question first. The gate stays a hook `ask`, and a declined prompt runs nothing.
