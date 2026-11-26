---
bump: minor
---

### Added

- `scripts/adopt.mjs` and the `/engineering-concepts:adopt` skill write adopted standards: the shipped concepts a person or team chooses, each as one line naming the concept, its id and its official source, into `<surface>.md` in the personal layer (`~/.claude/standards/`) or the repository's team standards root, and add that file's row to the layer's index. Without `--yes` the script prints exactly the text it would write: the whole file when new, the appended lines otherwise, and the index row. A concept already in the file is skipped and an existing row is kept; an unknown concept, a surface named `readme`, a backslash in the `Applies when` text, a team root with no standards index, an unreadable `.claude/standards.yaml` or a standards root outside the repository is refused with nothing written. A file past the standards contract's 200-line budget is written with a warning. With no personal index, the file still loads, since the standards folder is then read file by file.
- `lookup.mjs --counterweights-of <id>,<id>` prints one line per counterweight and per conflict of each id, so a stage that loads an adopted standards file reads them from the shipped data instead of a copy in the file.
