---
bump: patch
---

### Changed

- `/testing:run-e2e`'s browser-tool rubric routes the user's signed-in Windows browser from WSL to `claude --chrome`, outside documented support: the `/chrome` dialog refuses on WSL, the extension must be signed in to the same claude.ai account, and `list_connected_browsers` should return a Windows browser. Recorded from the live test on Claude Code 2.1.296 in ADR 0056; rechecked on each release.
