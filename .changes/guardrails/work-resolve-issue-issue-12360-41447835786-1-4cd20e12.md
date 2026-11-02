---
bump: patch
---

### Fixed

- `block-dangerous-git` now blocks a destructive git command placed after a `#` that Bash reads
  as literal text, not a comment, such as `a=(x)#; git reset --hard` or `echo $(:)#; git reset
  --hard`. The shared `hook-utils.sh` Bash command parser keeps a `#` right after the closing `)`
  of an array assignment, an extglob, `$(…)`, `$((…))` or `<(…)`, or after a closing backtick, in
  its word, as Bash does. Those frames now stay open across `;`, `|`, `&` and newlines inside
  them, and a `case` pattern's `)` no longer closes one.
- A comment or quote inside backticks now ends at the closing backtick, as in Bash, so
  ``echo `#`; git reset --hard`` is blocked.
- For `!(x)#` and `f@()#`, where the `#` is literal with `shopt -s extglob` and a comment
  without it, the parser now reports the commands of both readings, so a command after the `#`
  is checked either way.
