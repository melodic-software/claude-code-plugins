# Changelog

All notable changes to the `core` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.0] - 2026-11-09

### Changed

- `core` now also installs `guardrails`, so a standalone `core` install gets the guard hooks that block secret leaks and destructive commands such as `git reset --hard`, force pushes and unguarded recursive deletes.

## [0.2.0] - 2026-11-09

### Changed

- `core` now installs the vital lifecycle set, from planning through the pull request and session handoff: planning, discovery, verification, toolchain, review, source-control, session-flow and work-items. It no longer installs the whole default-on set. CI now fails when a member is missing from the catalog or is not default-on, in place of requiring the list to equal the default-on set.
- On update, `core` no longer installs `guardrails` or the other default-on plugins outside the set, so `claude plugin prune` can remove the ones nothing else needs. If you relied on `core` for `guardrails`, enable it directly.

## [0.1.0] - 2026-10-28

### Added

- A dependency-only bundle: installing `core` installs the catalog's default-on plugins, listed as
  unversioned `dependencies` in its manifest. No skills, agents or hooks. `core` is off by default,
  and CI fails when its list differs from the default-on set.
