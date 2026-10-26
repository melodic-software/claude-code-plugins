---
bump: minor
---

### Added

- `patch-rules.json` has a `docs` row for a markdown-only patch. It allows only a path ending in `.md` (the new `markdown` allow rule). Besides the universal set it refuses a path under a `skills/` directory at any depth and a `SKILL.md` anywhere (the new `skills` and `skill-md` refusals, which apply only to a row that names them), each escalating `patch-protected-path`. Its cap, commit, moved-head path and reasons match `default`. No push job selects it yet: fix-docs's `apply-docs-patch` job keeps the `default` row until `pr-refine.yml` passes `patch-prepare: docs`.
