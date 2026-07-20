# Changelog

All notable changes to the `domain-driven-design` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.0]

### Changed (breaking)

- **`ubiquitous-language` skill renamed to `curate-language`** (fleet conformance wave: naming
  grammar). Invocation changes from `/domain-driven-design:ubiquitous-language` to
  `/domain-driven-design:curate-language`; behavior is unchanged. The new name follows the
  verb-object skill-naming grammar. The domain term *ubiquitous language* the skill stewards keeps
  its name — only the skill's invocation token changed. Consumers (including the `planning` plugin's
  cross-plugin invocation) must update to the new token.

## [0.1.0]

### Added

- **Initial release.** `/domain-driven-design:ubiquitous-language` — moved from the
  `planning` plugin, where it lived as `/planning:domain-modeling`. The skill maintains
  the consuming project's active ubiquitous-language glossary (canonical terms, rejected
  synonyms, what-it-IS definitions, routing among already-known bounded contexts) and
  explicitly refuses bounded-context discovery — the old name over-promised modeling; the
  concern is DDD language stewardship. `planning` now declares a dependency on this
  plugin, so its pipeline keeps invoking the skill cross-plugin.
