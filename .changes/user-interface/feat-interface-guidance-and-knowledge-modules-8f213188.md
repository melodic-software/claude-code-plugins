---
bump: minor
---

### Added

- `reference/concerns.json`, the interface concern table, with `reference/concerns.schema.json` and `scripts/lib/concerns-validate.mjs`. Each row names the reference files (spokes) a concern reads, its routing concerns and its audit order; the first row is `motion`.
- `design.concern_spoke_cap` (default 2, an integer of at least 1) bounds how many concern spokes one `/user-interface:design` pass loads.

### Changed

- The animation audit skill is now `/user-interface:audit`. It takes a scope, `diff` (the default), `tree`, or `launch`, which walks every lane in the concern table's audit order, one pass each, and reviews one concern lane per pass. The motion lane keeps the `opportunities` and `performance` sub-modes, now in its procedure file `skills/audit/reference/motion.md`. `--fix` still applies one finding at a time after a yes, at every scope.
- `/user-interface:design` Step 3 loads spokes for the concerns the project's own system does not cover from the concern table, up to the cap, and names the rest as next steps.
