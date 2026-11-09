---
bump: patch
---

### Fixed

- The plugin-level destructive guard no longer denies a Bash command whose only mention of `hygiene.py` is inside a quoted argument containing a parenthesis, such as `gh issue create --title "Simplify hygiene.py (part 1 of 4)"`. A `(` inside a whole-word quote now counts as text when it follows a space and an ordinary word. The quoted argument then gets the same check as one without parentheses. Every parenthesis still fails closed when the command contains a backslash, a bash or zsh reserved word (such as `time`, `if`, `coproc` or `repeat`), or the word `fish`, and in every PowerShell command.
- The guard now gates a Bash command that names the bundled engine's path inside a larger word, such as an `awk -v c=<engine>` operand, a `perl -e ... c=<engine>` argument, or a `bash -c "exec <engine> scan"` payload. It checks each path-like part of every word against the engine file.
