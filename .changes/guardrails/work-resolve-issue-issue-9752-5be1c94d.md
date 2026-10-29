---
bump: minor
---

### Added

- `block-root-delete-target` judges a `find` that deletes the way it judges a recursive `rm` ([#9752](https://github.com/melodic-software/claude-code-plugins/issues/9752)): `find -delete`, or an `-exec`, `-execdir`, `-ok` or `-okdir` whose command word is `rm`, `rmdir` or `unlink`. Each start point is a target, `.` when none is given, read the way GNU and BSD find both read their leading options, and under `-H`, `-L` or `-follow` a start point that is a symlink is judged by where it points. A start point at a root, at home, outside the allowed roots or on a protected tree is refused, and one strictly inside the git toplevel, a temp root, the session scratchpad or an allowed root passes. A find delete started at the git toplevel is refused as a directory holding a `.git` whatever its filters, because find descends into `.git`.
