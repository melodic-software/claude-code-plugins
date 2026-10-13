---
bump: patch
---

### Changed

- **`pydeps.py` always hands over to the first supported Python.** Whatever Python starts it, it now runs under the first `python3` or `python` on PATH at 3.12 or later (on Windows, else one that `py -0p` lists), not only when the starting Python is below 3.12, so the hook and every skill run use the same install directory. With `ANIMATION_PYDEPS_INTERPRETER` set, it stays on the Python that started it, which pins a version.

### Fixed

- **One install hook and `pydeps.py` across animation, speech and explainer-video.** Both are now generated copies of `lib/install-python-deps.sh` and `lib/pydeps.py`, kept in step by `scripts/sync-shared-copies.sh`, with each plugin's settings in `hooks/install-python-deps.conf` and `scripts/pydeps.json`. The explainer-video fixes reach animation and speech: the handover to a supported Python drops a foreign `PYTHONHOME`, `PYTHONPATH` and uv marker, Windows finds a python.org install through `py -0p`, a crashed handover is a one-line notice with a repair line, and `pydeps.py check` reports the install.

### Security

- **Files in the project no longer run inside `pydeps.py`.** The version probe runs isolated (`-I`), the load probe and pip run without the working directory on the module path (`-P`), and on Windows the interpreter search skips the working directory, so a `python3.bat` or `sysconfig.py` in the project is never run. A config with no source builds passes pip `--only-binary :all:` again, so no lock line can build from source.
