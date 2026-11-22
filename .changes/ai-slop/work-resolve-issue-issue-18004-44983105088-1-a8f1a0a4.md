---
bump: minor
---

### Added

- `/ai-slop:setup apply` moves an old `~/.claude/ai-slop.json` into the personal override `<home>/ai-slop.local.yaml`. It refuses until the override path is gitignored. It previews the merged file and asks for a yes. Where both files set a key, the existing override's value wins, and the preview names that key. After writing, it re-runs `--show-config` to confirm each moved key resolves from the override, and only then deletes the old file. `setup check` names the old file and whether it is read ([#18004](https://github.com/melodic-software/claude-code-plugins/issues/18004)).

### Changed

- The detector reads the config-cascade layers: the team file, then the personal override. Every ai-slop key is a convention for the repository's own markdown, so there is no `userConfig` option. While the repository has no personal override, the old `~/.claude/ai-slop.json` is still read in the personal layer's place, so its values now win over the team file's. With an override present, the old file is not read. Each run prints one warning naming the old file, its new location and `/ai-slop:setup apply`. The warning goes to stderr, or into the `--show-config` output beside the layers ([#18004](https://github.com/melodic-software/claude-code-plugins/issues/18004)).
