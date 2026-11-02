---
bump: patch
---

### Changed

- The `SessionStart` hook `install-python-deps.sh` starts no process while its ready stamp holds: after a successful install with an interpreter found on PATH, `pydeps.py` writes `<data>/python/.hook-ready`, and the hook skips the interpreter probe, `cygpath` and the numpy and onnxruntime load probe until the plugin root, a candidate interpreter's resolution, that interpreter's file, `requirements.txt`, `pydeps.py` or `pydeps.json` changes, or the installed set is gone. `pydeps.py run` drops the stamp when the set is missing or a script exits non-zero, and `check` when a row fails, so the next session start probes and rebuilds ([#12258](https://github.com/melodic-software/claude-code-plugins/issues/12258)).
