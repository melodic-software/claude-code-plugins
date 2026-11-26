---
bump: minor
---

### Added

- `scripts/adopt.mjs` and the `/engineering-concepts:adopt` skill write adopted standards: the shipped concepts a person or team chooses, each as one line naming the concept, its id and its official source, with one line under it per counterweight or conflict, into `<surface>.md` in the personal layer (`~/.claude/standards/`) or the repository's team standards root, and add that file's row to the layer's index. Without `--yes` the script only prints what it would write. A concept already in the file is skipped and an existing row is kept; an unknown concept, a team root with no standards index, an unreadable `.claude/standards.yaml` or a standards root outside the repository is refused with nothing written. With no personal index, the file still loads by glob discovery.
