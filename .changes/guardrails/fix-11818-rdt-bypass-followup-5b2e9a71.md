---
bump: patch
---

### Fixed

`block-root-delete-target` now also refuses `rm -rf $S/x` when the command sets `S` through a name-taking option with the name glued on (`printf -vS`, `read -aS`, `wait -pS`), a quoted spelling of a setter (`printf -v"S"`, `read '-aS'`, `printf -v "S"`), a nameref flag after another declare flag (`declare -g -n S=R`), or a subscript assignment (`S[0]=`), since each can give `S` a value with a blank. A command that holds a setter builtin and any `$'...'` or `$"..."` word also refuses it, because those can spell the name in escapes (`printf -v $'\x53'`). A flag that takes no name (`read -r line` beside `$r/x`), `S[1]` inside a string, and `$'...'` in a command with no setter builtin stay allowed. These refusals were not replayed against the corpus.
