---
bump: minor
---

### Removed

- **`round.py` takes no page text on its command line.** The `reply`, `revise`, `note-reply`, `record-terminal`, `archive`, `reconfirm` and `group` commands are gone; each is an `apply` op, and calling one of the old commands is refused with a pointer to `round.sh --dir DATA_DIR apply --file OPS`. `add` reads the question only from `--file` and drops its text flags (`--short`, `--title`, `--rec`, `--facts`, `--basis`, `--waits-on`, `--commit`, `--alt`); `--id`, `--group`, `--stage`, `--round`, `--depends`, `--follow-up-of`, `--supersedes` and `--waiting` still override its fields.

### Changed

- **`supersede` and `resolve` read their text from a file.** `supersede --proposes TEXT` is now `--proposes-file P`, and `resolve reconfirm --note TEXT` is now `--note-file N`. Neither command accepts an abbreviated option, so an old `--proposes` or `--note` is rejected instead of being read as a file name.
