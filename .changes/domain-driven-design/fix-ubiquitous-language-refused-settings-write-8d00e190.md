---
bump: patch
---

### Fixed

- `/domain-driven-design:ubiquitous-language` no longer writes a settings file to the plugin data folder before resolving the glossary file names. It passes the userConfig values to `glossary-settings.mjs` on stdin (`--user-config -`) through a quoted heredoc, so a session that refuses that write still applies the team and personal layers. When the resolver run itself is refused, the skill uses the default names and says the settings were not resolved.
