---
bump: patch
---

### Fixed

- `plugin-eval`'s short-`TMPDIR` advice now points at a directory on disk (`$HOME/.ev` when that
  stays within 24 characters) instead of `/run/user/<uid>/ev`, and says why: that tmpfs is small,
  and kept `--keep-temp` sandboxes can fill it, failing every eval on the host and breaking the
  session sockets stored there
  ([#11727](https://github.com/melodic-software/claude-code-plugins/issues/11727)).
