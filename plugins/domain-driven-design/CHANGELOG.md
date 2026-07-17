# Changelog

All notable changes to the `domain-driven-design` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0]

### Added

- **Initial release.** `/domain-driven-design:ubiquitous-language` — moved from the
  `planning` plugin, where it lived as `/planning:domain-modeling`. The skill maintains
  the consuming project's active ubiquitous-language glossary (canonical terms, rejected
  synonyms, what-it-IS definitions, routing among already-known bounded contexts) and
  explicitly refuses bounded-context discovery — the old name over-promised modeling; the
  concern is DDD language stewardship. `planning` now declares a dependency on this
  plugin, so its pipeline keeps invoking the skill cross-plugin.
