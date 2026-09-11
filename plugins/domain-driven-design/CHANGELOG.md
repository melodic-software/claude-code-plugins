# Changelog

All notable changes to the `domain-driven-design` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.3]

### Changed

- **Manifest description drops its em dashes.** Wording only; the plugin's behavior, options, and defaults are unchanged. The description renders into `docs/CATALOG.md`, which the repository's em-dash gate reads.

## [0.3.2]

### Changed

- **curate-language:** the invocation section states the current relationship with the planning
  plugin (invoke when installed) instead of a manifest dependency that no longer exists, and drops
  the unreachable "when unavailable" guidance addressed to other plugins' authors; the body defers
  the convention-resolution ladder to `context/glossary-contract.md` instead of carrying a shorter
  divergent copy, and the read gate covers convention resolution as well as writes. The README's
  install note says the same.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.3.1]

### Changed

- **Instruction-surface punctuation.** Replaced em dashes in the plugin README
  with periods. YAML frontmatter and the `plugin.json` description are
  unchanged. No behavior change.

## [0.3.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command. The
  slash-command picker then echoed that back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

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
  its name. Only the skill's invocation token changed. Consumers (including the `planning` plugin's
  cross-plugin invocation) must update to the new token.

## [0.1.0]

### Added

- **Initial release.** `/domain-driven-design:ubiquitous-language`, moved from the
  `planning` plugin, where it lived as `/planning:domain-modeling`. The skill maintains
  the consuming project's active ubiquitous-language glossary (canonical terms, rejected
  synonyms, what-it-IS definitions, routing among already-known bounded contexts) and
  explicitly refuses bounded-context discovery. The old name over-promised modeling. The
  concern is DDD language stewardship. `planning` now declares a dependency on this
  plugin, so its pipeline keeps invoking the skill cross-plugin.
