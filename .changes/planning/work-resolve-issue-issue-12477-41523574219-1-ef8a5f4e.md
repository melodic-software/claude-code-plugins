---
bump: minor
---

### Added

- `wayfind`: two settings in `docs/conventions/planning.yaml`. `wayfind_research_start` (default `auto`) starts a research item without asking when only research is on the frontier, and asks first otherwise. `wayfind_hitl_concurrency` (default `1`) caps how many `needs-human` items of one map can be claimed at once across sessions. Both are in the schema and in `reference/config.md` (#12477).
- `wayfind`: shared work files go on one dossier branch per map. The map's Notes link it, and it is deleted when the map closes (#12477).

### Changed

- `wayfind`: absorbs the owner-approved parts of Matt Pocock's wayfinder (#12477). Interview is the entry. Chart reads an existing interview ledger; with none, it offers the interview preloaded and runs it inline. The user confirms the destination before any item exists. Items are created first, and their edges and cross-references are written in a second pass with real ids and absolute URLs. A bare run proposes `chart` and waits. `work` takes an optional item and defaults to the first frontier item in creation order. It reads the map body and child list, opening an item's body only when needed, and consults the skills the map's Notes list. `needs-human` marks only items that need the user's intent or vision, whatever their type. No Notes line overrides "plan, don't do". The map closes to `/planning:prd`, `/work-items:decompose` or `/work-items:work`, or to a decision record or general summary, and the destination skill reads Decisions-so-far and the resolution comments. The `wayfind-closed-plan-destination` case now expects `/work-items:decompose`.
