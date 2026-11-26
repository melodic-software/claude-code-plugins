---
bump: none
---

Comments outside the necessary posture are removed from the source-control hooks, libraries, scripts and tests; 14 scripts print their `--help` from a heredoc instead of their header comment, and tests now pin the remove gate's symlink and non-directory refusals, the containment gate's `~/` expansion, and exec-bit-check's quoting of a newline in a path.
