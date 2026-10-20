---
bump: minor
---

### Added

- `video-digest` has an `asr_python` option naming the Python interpreter that imports `faster_whisper`. ASR detection and the readiness check probe it before `python`, `python3` and `py`, so a venv works on a machine whose default Python refuses `pip install --user`. Unset, detection is unchanged. Nothing is installed.
- `video-digest` Prerequisites carry a copyable `uv` venv recipe for faster-whisper, with the `av<19` pin, a pointer to the upstream fix, and a recheck trigger for the faster-whisper release that ships it. Every source's `run.mjs` invocation passes `--asr-python` when the option is set.

### Fixed

- The ASR runner script adds each existing `site-packages/nvidia/*/bin` directory as a DLL directory on Windows, so CUDA libraries installed as `nvidia-*` wheels load without PATH edits. It is a no-op elsewhere.
