---
bump: major
---

### Changed

- `/session-flow:handoff`, `/session-flow:retro` and `/session-flow:clean-stop` take `--unattended` in place of the bare word `unattended`, accepted anywhere in their arguments. The bare word no longer marks a run unattended: in `handoff` it is read as the topic or purpose text like any other word, and `retro` and `clean-stop` stop and name `--unattended`. The argument hints list `--unattended` after the action, and the evals pass the flag.
