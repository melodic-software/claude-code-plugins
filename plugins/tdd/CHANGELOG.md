# Changelog

All notable changes to the `tdd` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.2.0]

### Changed

- Renamed the `tdd` skill → `principles`. Update any `/tdd:tdd` invocations to `/tdd:principles`;
  the plugin ID (`tdd`) and marketplace listing are unchanged, only the skill's leaf name moved.
