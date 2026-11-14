---
bump: minor
---

### Added

- `ready` hands the pull request to `/review:reviewer-media` last, on the confirmed head, and `monitor` hands it over at entry and after each round's push, so a request label added after `ready` is honored. Neither hand-off gates anything.
- `media shows --facts <file>` prints the commit a pull request's reviewer-media section shows, read from a `view` facts file with no forge call, so a caller never parses the section itself.
- `view` reports `isCrossRepository`, `true` when the head is in a fork or a fork since deleted.

### Changed

- `media claim` refuses (exit 3, `failed`) a head commit that already has its failure comment from the signed-in account or a bot account, so no caller builds on it again.
