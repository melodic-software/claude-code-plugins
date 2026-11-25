---
bump: minor
---

### Added

- The bundled standards contract is at 1.3.0, which adds personal subscriptions: the repositories the user-global index lists in `standards_repositories`, each a personal layer beneath the user's own standards files and every team-tracked one. `scripts/org-standards.sh subscriptions` reports that it cannot read them in this plugin until it bundles `lib/yaml-subset.awk`.
