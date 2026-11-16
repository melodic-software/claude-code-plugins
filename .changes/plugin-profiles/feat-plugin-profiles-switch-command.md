---
bump: minor
---

### Added

- `/plugin-profile` switches the folder's profile in a running session without a model turn: a picker of the profiles, the `apply --dry-run` preview, and a confirm. It writes the entries that switch plugins on, runs `/reload-plugins` once when the next turn ends, then writes the entries that switch plugins off, which stay loaded until the next session start. A switch that turns on a plugin with an MCP or language server names it and says the next message re-reads the whole conversation. It refuses when `remember_folder_profile` is false or the session runs from a one-session file, saying how to start a session in that profile. The command needs Claude Code 2.1.287 or later; `apply` does not.
- `profiles.mjs list [--json]` names the profiles a folder apply can use with their descriptions, and `apply --dry-run --json` prints the preview as one object.
- `apply --defer-off` is refused in a session that `PLUGIN_PROFILES_SESSION` names.
