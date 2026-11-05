---
bump: minor
---

### Removed

- `/ai-slop:audit` no longer reads the repository's `.claude/ai-slop.json` and
  `.claude/ai-slop.local.json`, deprecated in 0.15.0. The team and personal layers are
  `<home>/ai-slop.yaml` and `<home>/ai-slop.local.yaml` only; `/ai-slop:setup` still offers to
  carry an old JSON team file's values into the YAML. The user-global `~/.claude/ai-slop.json`
  layer is unchanged.
