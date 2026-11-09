---
bump: patch
---

### Fixed

- The plugin-level destructive guard no longer denies a Bash command that names `hygiene.py` only inside a quoted argument containing a parenthesis, such as `gh issue create --title "Simplify hygiene.py (part 1 of 4)"`. A `(` inside a whole-word quote now counts as text when it follows a space and an ordinary word. The quoted argument then gets the same check as one without parentheses. A run of the engine is still gated in each of these cases: called by path, after an interpreter, as the first word of a quoted payload, beside an unquoted operator or expansion, or inside a quoted subshell (`bash -c "( ... )"`). Every parenthesis still fails closed when the command contains a backslash or a Bash reserved word such as `time`, `if` or `coproc`, and in every PowerShell command.
