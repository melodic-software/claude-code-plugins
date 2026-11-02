---
bump: patch
---

### Fixed

- The shared `hook-utils.sh` Bash command parser keeps a `#` right after the closing `)` of an
  array assignment, an extglob, `$(…)`, `$((…))`, `<(…)` or `>(…)`, or after a closing backtick,
  in its word, as Bash does, instead of reading it as a comment that hid the rest of the line.
  Those frames now stay open across `;`, `|`, `&` and newlines inside them, a `case` pattern's
  `)` no longer closes one, and `case` or `esac` inside arithmetic is read as a variable name.
- A comment, a quote of any kind, a here-doc delimiter or a here-doc body inside backticks now
  ends at the closing backtick, as in Bash; an escaped backtick does not close it, and outside a
  comment or quote it opens or closes a nested substitution whose commands are read.
- Case statements follow Bash's pattern-position rules: a pattern spelled `case` opens nothing,
  `esac` after `|` is a pattern, `case x in esac` closes on one line, and `\;;` is a word and a
  `;`, not a clause end. Inside an extglob or arithmetic a `#`, `<` or `>` is literal text.
- A here-doc takes its body only at a newline on the level where it was read, so one read
  before a `$(…)`, backtick, `a=(…)` or `@(…)` that spans lines takes its body after the line
  where that construct closes; a syntax error inside `a=(…)` cancels the line's here-docs.
- For `!(x)#` and `f@()#`, where the `#` is literal with `shopt -s extglob` and a comment
  without it, the parser now reports the commands of both readings, and `HOOK_HEREDOC_BODIES`
  lists each here-doc body once, in source order.
