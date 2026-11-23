---
bump: minor
---

### Added

- A Caller contract section in `reference/vendors.md` for skill steps that ask `/multi-agent:route vendors` which vendor runs a task: with `vendors.auto_delegation` off, route returns only `run here` and the step runs as before with no extra output; with it on and a vendor other than Claude chosen, the step sends its task text through route's `delegate` script and Claude reviews the report (and, for `task`, the changed files), which replaces the subagent's; text the user or caller did not write is framed as data; a skill asks route once per run per work type and passes route's `delegate:` line back with each later task; each call site carries one seam-phrased sentence.
- `skills/route/scripts/delegate --use investigate` runs `external-agents run <product> --use investigate --mode read-only`; `--use task` (the default) keeps `--use task --mode write`. Every other external-agents flag is still refused.
- `/multi-agent:route vendors` step 12 delegates `coding`, `web-ui` and `knowledge` work: with auto-delegation on and a non-Claude vendor chosen it prints one `delegate:` line naming the product, `--use` and any non-default model and effort, and runs a caller's brief through `delegate`. With auto-delegation off its output is unchanged.
