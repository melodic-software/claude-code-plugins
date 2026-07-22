# Changelog

All notable changes to the `education` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.2]

### Changed

- `/education:explain` description gains a disjoint-trigger boundary vs the new
  `adhd:digest`: `explain` changes ALTITUDE (plain words, lossy), `digest`
  changes STRUCTURE (faithful restructure, no altitude loss). This keeps the two
  auto-firing skills from colliding on the shared "previous response" default
  target — routing is on intent, not overlapping phrases. All existing `explain`
  trigger keywords are preserved.

## [0.5.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.5.0]

### Added

- New `quiz-me` skill (`/education:quiz-me`) — a post-work comprehension
  check. After a change is complete it generates a self-contained HTML
  report of what was done (context, intuition, decisions) with a quiz at
  the bottom the user answers, verifying that the HUMAN absorbed the work
  rather than the artifact. Non-gating by default; the new `quiz_policy`
  userConfig (`off`, `on-request`, `always`, `above-threshold`) tunes how
  often a quiz is offered, never whether the merge is blocked. A
  `recall <query>` action answers "what did we do
  on <ticket>" from a retained report library first, git/tracker
  archaeology second. Reports are keyed on repo identity and stored under
  `${CLAUDE_PLUGIN_DATA}` (or the new `report_library_dir` userConfig),
  never in the consuming repo's tree.

### Changed

- The plugin now declares `userConfig` (`quiz_policy`,
  `report_library_dir`), both optional with defaults that preserve
  zero-config behavior. The README Configuration section documents them.

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
