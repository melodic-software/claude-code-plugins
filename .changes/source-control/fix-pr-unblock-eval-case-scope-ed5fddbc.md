---
bump: patch
---

### Fixed

- The `comments --ci` review-thread tool's `check-paths` and `record` now also allow a file in the `plugins/<p>/` directory a kept thread's path sits in, except one under `hooks/`, `.claude-plugin/` or a `.claude/` directory, a `CLAUDE.md` or `AGENTS.md`, or a `.sh`, `.py`, `.mjs`, `.js` or `.ts` file, and a test file (`test_*.py`, `*_test.py`, `*.test.*`, `*.spec.*`) in the same directory as a kept thread's path. `.github/` stays refused.
