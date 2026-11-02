---
bump: patch
---

### Fixed

- `block-dangerous-git` now blocks a destructive git command placed after a `#` that Bash reads
  as literal text, not a comment, such as `a=(x)#; git reset --hard` or `echo $(:)#; git reset
  --hard`. The shared `hook-utils.sh` Bash command parser keeps a `#` right after the closing `)`
  of an array assignment, an extglob, `$(…)`, `$((…))` or `<(…)`, or after a closing backtick, in
  its word, as Bash does. Those frames now stay open across `;`, `|`, `&` and newlines inside
  them, a `case` pattern's `)` no longer closes one, and `case` or `esac` inside arithmetic is
  read as a variable name, so `echo $((case))#; git reset --hard` is blocked.
- A comment, a quote of any kind, a here-doc delimiter or a here-doc body inside backticks now
  ends at the closing backtick, as in Bash, so ``echo `#`; git reset --hard`` is blocked; an
  escaped backtick does not close it, and outside a comment or quote it opens or closes a nested
  substitution whose commands are checked. A case pattern spelled `case` no longer opens a case
  statement.
- For `!(x)#` and `f@()#`, where the `#` is literal with `shopt -s extglob` and a comment
  without it, the parser now reports the commands of both readings, so a command after the `#`
  is checked either way. `HOOK_HEREDOC_BODIES` still lists each here-doc body once, in source
  order.
