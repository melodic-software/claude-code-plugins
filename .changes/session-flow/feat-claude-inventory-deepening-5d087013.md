---
bump: patch
---

### Changed

- `transcript_dirs.sh` delegates project directory resolution to one invocation of the shared Python 3.10-compatible `lib/claude_projects.py` resolver while keeping the pure-Bash exact-match fallback and `gap:` notice when Python 3.10+ is absent.
