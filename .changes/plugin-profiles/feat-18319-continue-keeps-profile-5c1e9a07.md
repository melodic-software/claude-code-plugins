---
bump: minor
---

### Changed

- `start -c` (and `claude -c` through the dotfiles `claude` function) continues the folder's last conversation in the profile that session started in, printing `Continuing this folder's last conversation in profile <name>.`; Claude Code still picks the conversation. It starts with the profile's own session file, never the plugins a `--profile-add` reopen added; after a session with no profile, or one resumed without its profile since, it starts with the folder's settings, a given `--profile` wins, and a recorded profile that no longer exists is named and skipped. The session-start hook writes the per-folder record, `sessions/by-folder/<sha256 of the folder's real path>.json`, for every session except `claude -p` and Agent SDK sessions (the `sdk-*` entrypoints), which `claude -c` skips, and sweeps it after 30 days like the by-id records.
- A resumed session that had no recorded profile and now runs in one gets a start-notice line saying so, beside the existing line for a session that moved from one profile to another.
