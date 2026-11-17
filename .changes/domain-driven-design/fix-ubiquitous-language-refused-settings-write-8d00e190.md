---
bump: patch
---

### Fixed

- `/domain-driven-design:ubiquitous-language` no longer writes a settings file to the plugin data folder before resolving the glossary file names. It passes the userConfig values to `glossary-settings.mjs` on stdin (`--user-config -`) through a quoted heredoc, so a session that refuses that write still applies the team and personal layers. When that run is refused, the skill runs the resolver once more without the user-level values, so the team and personal layers still apply, and says the user-level settings were not applied.
