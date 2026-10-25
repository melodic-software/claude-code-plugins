---
bump: minor
---

### Changed

- The team layer of the bugs settings moves to `docs/conventions/bugs.yaml`, checked against the new `schemas/bugs.schema.json`, with team prose and `## Gotchas` in `docs/conventions/bugs.md` beside it. `/bugs:scan` reads `lanes` and `filing_posture` from the YAML, `concat-gotchas.sh` reads the team gotchas from the Markdown file, and `/bugs:setup apply` writes the YAML and carries every value of an existing `.claude/bugs.md` into it.

### Deprecated

- `.claude/bugs.md` as the team layer. For one release it is still read: its YAML block while `docs/conventions/bugs.yaml` is absent, and its `## Gotchas` while `docs/conventions/bugs.md` is absent.
