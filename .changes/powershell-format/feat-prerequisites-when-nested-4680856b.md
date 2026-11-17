---
bump: patch
---

### Changed

- The SessionStart probe reports a missing `pwsh` only where a `PSScriptAnalyzerSettings.psd1` sits in the project directory or above it, or is tracked anywhere in its repository, so a repository whose only settings file is in a subdirectory still gets the line and one with none hears nothing.
