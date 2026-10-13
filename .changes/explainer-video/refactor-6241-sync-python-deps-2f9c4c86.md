---
bump: patch
---

### Fixed

- **One install hook and `pydeps.py` across animation, speech and explainer-video.** Both are now generated copies of `lib/install-python-deps.sh` and `lib/pydeps.py`, kept in step by `scripts/sync-shared-copies.sh`, with each plugin's settings in `hooks/install-python-deps.conf` and `scripts/pydeps.json`. The explainer-video fixes reach animation and speech: the handover to a supported Python drops a foreign `PYTHONHOME`, `PYTHONPATH` and uv marker, Windows finds a python.org install through `py -0p`, a crashed handover is a one-line notice with a repair line, and `pydeps.py check` reports the install.

### Security

- **Files in the project no longer run inside `pydeps.py`.** The version probe runs isolated (`-I`), the load probe and pip run without the working directory on the module path (`-P`), and on Windows the interpreter search skips the working directory, so a `python3.bat`, `sysconfig.py`, `numpy.py` or `pip` package in the project is never run.
