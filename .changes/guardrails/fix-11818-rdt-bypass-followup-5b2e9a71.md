---
bump: patch
---

### Fixed

`block-root-delete-target` now also refuses `rm -rf $S/x` when the command sets `S` through a name-taking option with the name glued on (`printf -vS`, `read -aS`, `wait -pS`), a quoted spelling of a setter (`printf -v"S"`, `read '-aS'`, `printf -v "S"`), a nameref flag after another declare flag (`declare -g -n S=R`), or a subscript assignment (`S[0]=`), since each can give `S` a value with a blank. A flag that takes no name, such as `read -r line` beside `$r/x`, stays allowed.
