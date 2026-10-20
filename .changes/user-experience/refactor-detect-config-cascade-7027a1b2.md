---
bump: patch
---

### Changed

- `scripts/detect.mjs` now reads the team file through a generated copy of the shared
  resolver `lib/config-cascade.mjs` (ADR 0075), as `user-interface` does. The detection output for
  a team file at the convention home is unchanged, and `--team FILE` still replaces the resolved
  team file. The resolver also applies a `user-experience.local.yaml` beside the team file over its
  keys, refuses a team file that is a symlink (the file is then skipped as unreadable), and reports
  a rejected value as a warning; a warning for a local value names the local file. Only the team
  file sets `version`.
