---
bump: patch
---

### Fixed

- `/harness-ops:plugins converge` no longer treats a user home directory as a project path. `fleet-state.sh` marks each project or local record whose `projectPath` is `$HOME`, `/home/<name>`, `/Users/<name>`, `C:\Users\<name>` or the WSL view `/mnt/<drive>/Users/<name>` with `projectPathIsHome: true`. `converge` reports such a row as BLOCKED and emits no command for it, because that directory's `.claude/settings.json` is user settings and a project-scope uninstall there would remove user-scope enables. `sync` leaves those records out of its divergence count and lists them in a `User-home project records` row.
