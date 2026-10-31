---
bump: patch
---

### Fixed

- **`extract-ssot`'s `verify` action runs `emit-verify-facts.sh` from a path that resolves.** The command cited the script through the literal skill-directory token, which does not expand in a spoke file. It now reads `<skill-dir>/scripts/emit-verify-facts.sh`, and `SKILL.md` gains a `## Spoke paths` section saying `<skill-dir>` is the skill's directory.
