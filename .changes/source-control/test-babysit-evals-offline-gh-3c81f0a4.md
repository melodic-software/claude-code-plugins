---
bump: none
---

The three babysit-loop eval cases now get the offline gh stand-in: each scaffold installs it serving the two pull requests its prompt names, and each case lists its own `gh-forge-path` plugin. `install.sh` takes `--dir` and `--extra-pr`, sets a git alias that runs the remote helper when the stand-in is not on PATH, and the stand-in records each call it served. The babysit-prs graders `forge-read`, `no-merge-recorded` and `no-resolve-recorded` keep their checks: `forge-read` still reads the trace, and the two record graders still pass on an empty record, since the eval sandbox may hold `.git` read-only so a run's record can stay empty. They are now `arm: with-only`, reported as with-arm indicators and left out of both arms' scores, because the no-plugin arm has no stand-in. Evals only, no skill text change.
