---
bump: patch
---

### Changed

- `/developer-experience:build-cli`'s No inherited handles rule now covers Windows ([#9507](https://github.com/melodic-software/claude-code-plugins/issues/9507)). A child created with handle inheritance on receives every inheritable handle the command holds, which can include the pipe the command's own output goes to. Redirecting a child's streams needs inheritance on, so the rule now says to pass an explicit handle list naming only the handles the child gets. It cites the Win32 `CreateProcessW` and `STARTUPINFOW` pages.
