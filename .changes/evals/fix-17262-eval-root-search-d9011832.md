---
bump: patch
---

### Changed

- `run-validity.py`'s `permission denials` check no longer fails a finished without-arm run for a denied `Grep` or `Glob` whose `path` is that run's own eval root (the sandbox holding its `out/trace.jsonl`): the arm lacks the plugin and looks for it in its own folder. That denial is now a warning, and the verdict line, which is all CI keeps in `validity.txt`, names each excused call with its tool, root and pattern. A `Glob` pattern that is rooted or holds `..`, a path under or above the root, another tool, a with-arm run and an unfinished run still fail ([#17262](https://github.com/melodic-software/claude-code-plugins/issues/17262)).
