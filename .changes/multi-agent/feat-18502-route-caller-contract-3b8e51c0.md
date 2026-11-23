---
bump: minor
---

### Added

- A Caller contract section in `reference/vendors.md`: with `vendors.auto_delegation` off a routed skill step runs as before with no extra output; with it on and a vendor other than Claude chosen, the step sends its brief through route's `delegate` script and Claude reviews the report, which replaces the subagent's; a skill asks route once per run per work type; each call site carries one seam-phrased sentence.
- `skills/route/scripts/delegate --use investigate` runs `external-agents run <product> --use investigate --mode read-only`; `--use task` (the default) keeps `--use task --mode write`. Every other external-agents flag is still refused.

### Changed

- `/multi-agent:route vendors` step 10 covers delegation for every work type, not only image work: with auto-delegation on and a non-Claude vendor chosen it prints one `delegate:` line naming the product, `--use` and any non-default model and effort, so a caller reuses it for the run.
