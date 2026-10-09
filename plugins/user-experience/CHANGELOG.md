# Changelog

All notable changes to the `user-experience` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0] - 2026-10-09

### Added

- `shape` skill: the front door. It runs detect, states the app's stage with its signals and the
  project's own evidence, and hands research planning to `plan-user-research`.
- `plan-user-research` skill: writes a discussion guide in the shared deliverable envelope, with
  an evidence label, an AI-use note and assumptions to test. It writes instruments only and never
  recruits or runs sessions.
- `reference/deliverable.md`: the envelope every deliverable carries.
- `reference/routing.json` and its schema (row contract version 1, group field `job`), seeded
  with `/user-interface:design` for heuristics and the UI hand-off.
- `scripts/detect.mjs`: the project's manifests, research and persona locations, analytics SDKs
  and last-commit age, the installed routes, and the routes marked present. Install detection is a
  generated copy of the shared `lib/installed.mjs`.
- Evals: `fires-shape`.
