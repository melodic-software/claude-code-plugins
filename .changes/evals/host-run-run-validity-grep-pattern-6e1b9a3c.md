---
bump: patch
---

### Fixed

- `run-validity.py`'s `permission denials` check no longer reads a grep pattern as a path that may be inside the plugin: a denied plain read pipeline of `cat`, `head`, `wc`, `grep`, `egrep`, `fgrep` and `sed -n` names only its absolute file operands, so `grep -n -E "a|b" "/x/f.js" | head -40` aimed outside the plugin can warn instead of failing the run. Grep's `-e`, `--regexp`, `-f`, `--file` and `--` forms are read the same way, a `-f` pattern file counting as a path.
