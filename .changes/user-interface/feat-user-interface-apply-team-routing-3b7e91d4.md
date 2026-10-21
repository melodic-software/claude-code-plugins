---
bump: minor
---

### Added

- `/user-interface:design` now applies the team file's `routing`. `scripts/detect.mjs --config` prints `routes` (the bundled rows with a team row overriding or adding a route, and `disable` and `deny` applied), `skipped` (each removed route, with the team file as its source) and `routing_notes` (a disclosure when the team file or a row could not be applied), and `installed` and `reachable` follow those routes. A team `routing.deny: [figma]` now takes effect.
