---
bump: patch
---

### Fixed

- `/domain-driven-design:ubiquitous-language` no longer writes a settings file to the plugin data folder before resolving the glossary file names, so a session that refuses that write still applies the team and personal layers. It passes the userConfig values to `glossary-settings.mjs` on stdin (`--user-config -`) as raw `name=value` lines through a quoted heredoc, so a value holding a quote needs no escaping. When that run is refused, the skill runs the resolver once more without the user-level values and says the user-level settings were not applied.

### Added

- The plugin declares `node` as an optional prerequisite in `prerequisites.json`, with the bundled prerequisites checker in `lib/`.
