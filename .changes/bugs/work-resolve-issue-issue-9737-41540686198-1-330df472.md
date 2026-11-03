---
bump: minor
---

### Removed

- The one-release read of `.claude/bugs.md` as the team layer. `/bugs:scan` reads `lanes` and `filing_posture` only from `docs/conventions/bugs.yaml`, and `concat-gotchas.sh` reads the team `## Gotchas` only from `docs/conventions/bugs.md`. `/bugs:setup` no longer reports or migrates the old file. A repository that still keeps its settings in `.claude/bugs.md` moves its YAML block's keys to `docs/conventions/bugs.yaml` and its `## Gotchas` section to `docs/conventions/bugs.md`, then deletes the old file.
