---
bump: patch
---

### Fixed

- The `list-scripts` test suite passes on Git for Windows ([#6527](https://github.com/melodic-software/claude-code-plugins/issues/6527)): the quote-in-path case and the symlink case (`leaves out link.md`) are skipped there, since a Windows path cannot hold a quote and a plain `ln -s` copies the file. Both assertions are unchanged on Linux.
