# Changelog

All notable changes to the `source-control` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.1]

### Changed

- Synced the pull-request verify-gate example to the reorganized taxonomy:
  `/verify-changes` / `/build` are now `/verification:confirm` / `/toolchain:build`.

## [0.3.0]

### Added

- `/resolve-conflicts` skill: intent-first resolution of in-progress merge/rebase/cherry-pick
  conflicts — both sides' history read before any hunk is edited, compose-by-default with
  evidence-gated side-dropping, a post-resolution semantic-conflict sweep (build/tests before
  done), and a hard never-`--abort` discipline. Ships three evals.

## [0.2.0]

### Added

- Readiness security-gate, mixed-actor, and three worktree evals.
