---
bump: minor
---

### Added

- `start --resume <id> --profile-add <plugin>` (and `claude --resume <id> --profile-add <plugin>` through the dotfiles `claude` function) reopens a conversation in its recorded profile with an installed plugin the profile switched off, and its dependencies, on for that conversation only. It takes a plugin id, a plugin name, `plugin:skill` or a skill name, never settings text; an ambiguous name is refused with its candidates, and a plugin that is not installed with its `claude plugin install` line. A later `claude --resume <id>` of that conversation keeps the plugin; `claude -c`, new sessions, `launch` and handoffs start without it. `status` and the start notice name the added plugins.
- In a one-session profile the session-start hook now tells the model how to reopen the conversation with an off plugin, through `additionalContext`, at start and again after compaction (the hook now also runs on `compact`, and there returns only that line).

### Changed

- Profile setup ends by offering `claude --profile <name>` for one session instead of a folder apply.
