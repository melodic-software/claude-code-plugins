---
bump: patch
---

### Fixed

- On Windows, `launch` prints a PowerShell line (`Remove-Item Env:...; claude --settings ...`) in place of the `env -u` line Windows cannot run; `argv` keeps its shape for scripts that build their own start.
