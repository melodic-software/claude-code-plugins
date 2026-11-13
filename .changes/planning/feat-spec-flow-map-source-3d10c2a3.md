---
bump: minor
---

### Added

- `prd` and `plan` accept a map issue as their source (`#<map>`, a qualified ID or the item URL). A new shared `context/map-source.md` says how to read it through `/work-items:track view --comments`: from a closed map, the closing comment that states every decision; from an open map, each Decisions-so-far line's resolution comment, following `superseded by` lines to the live decision. The decisions are settled answers that are not asked again, and the map's open items become open questions.

### Changed

- `prd` and `plan` (its publish step) write every tracker link as the item's title linked to its absolute URL, never a bare `#<n>`.
