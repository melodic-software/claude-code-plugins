---
bump: patch
---

### Fixed

- The plugin-level destructive guard no longer denies a Bash command whose only mention of `hygiene.py` is inside a quoted argument containing a parenthesis, such as `gh issue create --title "Simplify hygiene.py (part 1 of 4)"`. A `(` inside a whole-word quote now counts as text when it follows a space and an ordinary word, and every `hygiene.py` sits inside quoted prose. The quoted argument then gets the same check as one without parentheses. Every parenthesis still fails closed in these cases: when `hygiene.py` also appears outside the quotes or as a quoted word by itself, when the command contains a backslash, a bash or zsh reserved word (such as `time`, `if`, `coproc` or `repeat`), or the word `fish`, and in every PowerShell command. Accepted residual: a quoted program that builds the engine's path from text inside the quote, such as `perl -e "chdir (shift) and exec (qw z ./hygiene.py z)" <scripts>`, is not gated. Its form without parentheses was not gated before either.
- The guard now gates a Bash command that names the bundled engine's path inside a larger word, such as an `awk -v c=<engine>` operand, a `perl -e ... c=<engine>` argument, or a `bash -c "exec <engine> scan"` payload. It checks each path-like part of every word against the engine file.
