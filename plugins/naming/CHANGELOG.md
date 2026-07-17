# Changelog

All notable changes to the `naming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0]

### Added

- **Initial release.** `/naming:name-it-better` — generate fresh name
  candidates by fanning out blind, fresh-context generators from distinct lenses
  (responsibility-literal, moment-of-use, domain-lore), score a shortlist against
  the consuming org's naming criteria, and recommend — the human always picks,
  never an auto-locked name. Optional `tournament` action adds elimination rounds
  with independent judges for high-stakes, hard-to-refactor names.
- Repo-agnostic: scores against the consuming project's declared naming
  conventions when present, degrading to the general criteria grounded in the
  skill's `context/sources.md` when none is declared.
