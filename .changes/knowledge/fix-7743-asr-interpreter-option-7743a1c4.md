---
bump: minor
---

### Added

- `video-digest` has an `asr_python` option naming the Python interpreter that imports `faster_whisper`. ASR detection and the readiness check probe it before `python`, `python3` and `py`, so a venv works on a machine whose default Python refuses `pip install --user`. Unset, detection is unchanged. Nothing is installed.
- `video-digest` Prerequisites carry a copyable `uv` venv recipe for faster-whisper, with the `av<19` pin and a recheck trigger for faster-whisper releases after 1.2.1.

### Fixed

- The ASR runner script adds each existing `site-packages/nvidia/*/bin` directory as a DLL directory on Windows, so CUDA libraries installed as `nvidia-*` wheels load without PATH edits. It is a no-op elsewhere.
