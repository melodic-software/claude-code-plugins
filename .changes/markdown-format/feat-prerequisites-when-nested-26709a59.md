---
bump: patch
---

### Changed

- The SessionStart probe reports a missing `markdownlint-cli2` only where a markdownlint config sits in the project directory or above it, or is tracked anywhere in its repository, so a repository with no config hears nothing about it.
