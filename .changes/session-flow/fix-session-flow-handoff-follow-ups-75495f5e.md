---
bump: patch
---

### Changed

- `save_point.py`, `tidy_work.py` and the hop-chain harness now say "handoff file" and "archive file"
  in their messages, `--help` text and comments; identifiers, frontmatter keys and paths are
  unchanged.
- `focus.py` and `away.py` share one file lock from `plugin_paths.py`, polled every 10 ms. Each
  keeps its wait; on timeout `focus.py` still skips the write, and `away.py` still raises, now a
  `TimeoutError` naming the lock file, which its handlers catch as before.
