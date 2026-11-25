---
bump: minor
---

### Added

- The bundled standards contract is at 1.3.0, which adds personal subscriptions: the repositories the user-global index lists in `standards_repositories`, each a personal layer beneath the user's own standards files and every team-tracked one. `scripts/org-standards.sh subscriptions` prints each layer with its checkout and its topic-filtered index, reading the list with the newly bundled `lib/yaml-subset.awk`.
