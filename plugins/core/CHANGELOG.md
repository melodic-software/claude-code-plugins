# Changelog

All notable changes to the `core` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0] - 2026-10-28

### Added

- A dependency-only bundle: installing `core` installs the catalog's default-on plugins, listed as
  unversioned `dependencies` in its manifest. No skills, agents or hooks. `core` is off by default,
  and CI fails when its list differs from the default-on set.
