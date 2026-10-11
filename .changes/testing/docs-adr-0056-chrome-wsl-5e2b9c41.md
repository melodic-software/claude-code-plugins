---
bump: patch
---

### Changed

- `/testing:run-e2e`'s browser-tool rubric routes the user's signed-in Windows browser from WSL to `claude --chrome`, outside documented support, and points at the live-test record in ADR 0056 (Claude Code 2.1.296) for the steps; rechecked on each release.
