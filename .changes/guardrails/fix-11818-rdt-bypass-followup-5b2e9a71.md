---
bump: patch
---

### Fixed

`block-root-delete-target` now also refuses `rm -rf $S/x` when the command sets `S` through an option argument glued to its letter (`printf -vS`, `read -aS`), a nameref flag after another declare flag (`declare -g -n S=R`), or a subscript assignment (`S[0]=`), since each can give `S` a value with a blank.
