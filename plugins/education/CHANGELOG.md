# Changelog

All notable changes to the `education` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.4.0]

### Added

- New `explain` skill (`/education:explain`) — a one-shot, plain-language
  sibling to the multi-session `teach` coach. It drops any concept, code,
  error, architecture, or the previous assistant response to genuinely plain
  words (concrete analogy, zero jargon), then layers altitude up only on
  request (high-school, then peer level). An empty argument targets the
  previous assistant response (anaphora), so "I don't get it" needs no topic
  named. Unlike `teach`, it auto-invokes on colloquial triggers, runs a Feynman
  gap check that surfaces an understanding gap instead of papering over it, and
  closes by offering `/education:teach topic <x>` for ongoing coaching.

## [0.3.2]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.3.1]

### Changed

- README Requirements now declare the skill's Bash + coreutils mechanics
  (`sha256sum`/`shasum`, `realpath`, `tr`, `sed`) with their Windows path
  (Git Bash bundles all of them), replacing the inaccurate "none beyond
  Claude Code" — cross-platform declaration wave.

## [0.3.0]

First versioned release covered by this changelog; see the git history of
`plugins/education/` for earlier changes.
