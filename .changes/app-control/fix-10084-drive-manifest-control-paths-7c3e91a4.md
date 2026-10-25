---
bump: patch
---

### Added

- Eval cases for a plugin control skill found only through a manifest path: a plugin eval case with a skills-folder plugin whose `commands` map points `control-shop` at a file outside `commands/`, and skill eval cases with a listed plugin whose `commands` path names a non-default folder beside a stale `commands/` file, and one whose `skills` path names an extra folder.

### Fixed

- `/app-control:drive` now finds a plugin's control skill at a path the plugin's manifest names. For each listed plugin it searches the skill and command files the plugin loads from its default folders and its manifest's `skills` and `commands` keys, located as the manifest reference says, keeps or drops a `commands` map entry's `source` file by the entry's key, and reads no path outside the plugin folder. A plugin kept in the repository's skills folder is searched the same way. Before, such a control skill was missed and drive fell back to its no-control-skill recipe.
