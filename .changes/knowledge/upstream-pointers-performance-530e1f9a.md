---
bump: patch
---

### Fixed

- docpage-digest: stop claiming a rendered WebFetch of a long page gives no truncation signal; point at the live WebFetch section instead.
- map-corpus: resolve a relative `library_dir` against the session working tree, as docpage-digest does, instead of `CLAUDE_PROJECT_DIR`.

### Changed

- Replace restated Claude Code behavior (plugin data lifetime, Read page limit, variable substitution, option storage scopes, worktree project directory) with live section pointers, name the probes behind the raw-channel observations, and keep one effort pointer record in dual-verification.md.
