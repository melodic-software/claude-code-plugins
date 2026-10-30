---
bump: patch
---

### Changed

- `/developer-experience:build-cli`'s No inherited handles rule now covers Windows ([#9507](https://github.com/melodic-software/claude-code-plugins/issues/9507)). A child given redirected streams starts with an explicit list of the handles it may inherit, naming only its null or file handles, and a child given none starts with inheritance off. The rule points at the Win32 `CreateProcessW` and `STARTUPINFOW` sections for why.
