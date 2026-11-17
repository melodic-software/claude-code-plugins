---
bump: patch
---

### Fixed

- The comment lint, the comment census and the comment-target ranking read shell scripts by
  POSIX and Bash token rules instead of pygments' Bash lexer. A `#` inside quotes, inside a
  word (`$base#frag`, `10#$n`), in `${#x}`, `$#` or a here-document body is no longer a
  comment, and a here-document whose body names its delimiter (`$STUB_LOG` under `<<'STUB'`)
  no longer flips the quote state for the rest of the file, which had both flagged quoted
  text and hidden real comments.
