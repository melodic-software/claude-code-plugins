---
bump: minor
---

### Added

- `block-cd-prefix` denies a Bash command that opens with `cd <path>` followed by `&&`, `;` or a newline and then runs `git` or writes to a relative path, which no permission allow rule matches. The reason says to run `git -C <abs path> ...` with absolute paths, and to write a multi-line commit message to a file for `git commit -F <file>`. `cd .` and a `cd` to the current directory pass. Kill switch: `block_cd_prefix_enabled`, on by default.
