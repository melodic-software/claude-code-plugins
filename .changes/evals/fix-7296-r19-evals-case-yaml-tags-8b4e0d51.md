---
bump: patch
---

### Fixed

- `run-validity.py` reads a case's top-level `case.yaml` tags as well as its `prompt.md` tags, so a `no-network`, `control` or `invocation-probe` tag on a case with no `prompt.md` now takes effect ([#7296](https://github.com/melodic-software/claude-code-plugins/issues/7296)).
