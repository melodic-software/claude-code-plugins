---
bump: none
---

Removes the redundant eval case `ck-notice-alone-installs-nothing`: `ck-hook-notice-read-only` runs the
same scaffold and notice with the same graders, and `ck-install-tempted-no-slash` checks the one
grader it lacked. No skill behavior changes.
