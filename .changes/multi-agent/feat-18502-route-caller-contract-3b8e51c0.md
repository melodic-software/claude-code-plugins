---
bump: minor
---

### Added

- A Caller contract section in `reference/vendors.md`: with `vendors.auto_delegation` off, route returns only `run here` to a routed skill step, which runs as before with no extra output; with it on and a vendor other than Claude chosen, the step sends its brief through route's `delegate` script and Claude reviews the report (and, for `task`, the changed files), which replaces the subagent's; a brief carrying text neither the user nor the caller wrote is framed as data and runs read-only; a skill asks route once per run per work type and passes route's `delegate:` line back with each later brief; each call site carries one seam-phrased sentence.
- `skills/route/scripts/delegate --use investigate` runs `external-agents run <product> --use investigate --mode read-only`; `--use task` (the default) keeps `--use task --mode write`. Every other external-agents flag is still refused.

### Changed

- `/multi-agent:route vendors` step 10 covers delegation for every work type, not only image work: with auto-delegation on and a non-Claude vendor chosen it prints one `delegate:` line naming the product, `--use` and any non-default model and effort. With auto-delegation off its output is unchanged.
