---
bump: patch
---

### Changed

- surface-journey test: the shell's applies and handles between page phases run `round` as a module, which reuses its cached bytecode instead of recompiling `round.py` on each call, and the pause before the last Notes reply waits only for the next whole second.
