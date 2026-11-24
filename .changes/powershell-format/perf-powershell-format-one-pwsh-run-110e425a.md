---
bump: patch
---

### Changed

- At pre-commit, PowerShell starts once per commit instead of twice: the `format` entry also lints the files it just formatted and leaves the result for the `lint` entry, keyed by each file's bytes and the settings file. The `lint` entry reports it with the same exit codes and messages, and starts `pwsh` itself when no matching result is waiting. A declined `lint` entry, or a `powershell-format-remote-lint` job skipped in `lefthook-local.yml`, makes `format` lint nothing. Format then lint on a 120-line file went from 0.759 s to 0.465 s (median of 5, one Linux host).
