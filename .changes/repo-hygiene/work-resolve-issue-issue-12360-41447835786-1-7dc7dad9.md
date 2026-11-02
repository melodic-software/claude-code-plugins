---
bump: patch
---

### Fixed

- The shared `hook-utils.sh` Bash command parser keeps a `#` right after the closing `)` of an
  array assignment, an extglob, `$(…)`, `$((…))`, `<(…)` or `>(…)`, or after a closing backtick,
  in its word, as Bash does, instead of reading it as a comment that hid the rest of the line.
  Those frames now stay open across `;`, `|`, `&` and newlines inside them, a `case` pattern's
  `)` no longer closes one, and `case` or `esac` inside arithmetic is read as a variable name.
- A comment or quote inside backticks now ends at the closing backtick, as in Bash; an escaped
  backtick does not close it.
- For `!(x)#` and `f@()#`, where the `#` is literal with `shopt -s extglob` and a comment
  without it, the parser now reports the commands of both readings, and `HOOK_HEREDOC_BODIES`
  lists each here-doc body once, in source order.
