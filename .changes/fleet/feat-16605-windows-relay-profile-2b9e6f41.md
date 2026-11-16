---
bump: minor
---

### Added

- The reach skill starts a relay turn or session on a Windows lane in the plugin profile the task names: one PowerShell script, sent on stdin to `powershell.exe -Command -`, finds `profiles.mjs` through `claude.exe plugin list --json`, runs `launch --unattended --json`, removes each variable `argv` names after `-u`, and starts `claude.exe` with the rest of `argv`. With plugin-profiles or `node` missing it starts without the profile and says so.
