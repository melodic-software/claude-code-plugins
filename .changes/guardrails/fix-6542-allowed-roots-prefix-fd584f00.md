---
bump: minor
---

### Added

- **block-root-delete-target name-prefix entries ([#6542](https://github.com/melodic-software/claude-code-plugins/issues/6542)).** A `block_root_delete_target_allowed_roots` entry that ends in one `*` after a literal name, such as `D:/worktrees/.tmp-*`, now allows a recursive delete of a direct child of that directory whose name extends the prefix by at least one character, compared by real path. The directory, the bare prefix, a sibling, anything below a matching child, a glob, a `..` escape and a matching symlink all stay refused. An entry holding a glob character granted nothing before, so no entry that already allowed something changes meaning.
