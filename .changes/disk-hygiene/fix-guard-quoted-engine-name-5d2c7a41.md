---
bump: patch
---

### Fixed

- The destructive guard now gates a Bash command that names the bundled engine's path inside a larger word, such as an assignment operand (`awk -v c=<engine>`, `tool --x=<engine>`, `perl -e ... c=<engine>`) or a quoted program (`bash -c "exec <engine> scan"`, `zsh -c "repeat 1 <engine> scan"`). It checks each path-like part of every word against the engine file.
