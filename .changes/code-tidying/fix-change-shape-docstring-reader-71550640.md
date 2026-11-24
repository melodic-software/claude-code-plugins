---
bump: patch
---

### Fixed

- `change-shape.py` no longer reads a `help=` keyword argument (or any other docstring-reader name used as a keyword argument or parameter name, directly after `(` or `,` and before `=`) as a run-time docstring read, so a docstring deletion in a file with argparse options can return DOCSTRING-ONLY. `help(...)`, `help` passed as a value, and any `__doc__` or `__dict__` token still return CODE-CHANGED.
