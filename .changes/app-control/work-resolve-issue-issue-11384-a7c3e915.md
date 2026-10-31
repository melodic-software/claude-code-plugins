---
bump: minor
---

### Added

- `/app-control:drive affected --base <ref> [--head <ref>]` maps a diff to the control skill's features and writes `affected.json`, launching nothing ([#11384](https://github.com/melodic-software/claude-code-plugins/issues/11384)). `scripts/affected_features.py` does the matching. With no control skill it writes empty features and the note `No control skill: nothing matched`.
- `--trusted-root <dir>` on every drive action reads control skills only from `<dir>` and from plugins whose folder sits under it, so a checkout under test cannot supply its own control skill.

### Changed

- The control-skill contract fixes the `sources` glob syntax: `**` matches across `/`, `*` and `?` match within one path segment. A plugin control skill's globs resolve against the root of the repository under verification.
