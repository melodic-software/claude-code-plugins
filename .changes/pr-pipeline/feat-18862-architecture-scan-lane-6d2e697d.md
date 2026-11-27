---
bump: minor
---

### Added

- A lane section takes `every-days` (an integer of at least 1, default 1): how many days a scheduled lane with a cadence gate waits after its last completed run.
- The `maintenance-scan-architecture` lane, shipped with `enabled: false`. Its no-model gate job stops a daily or dispatched run as `lane-off`, `at-cap` (the open `source: architecture-improve` issues reach `find_open_item_cap`, default 5, from the improvement config cascade), `not-due` or `no-merges`; a dispatch's `force` input skips only `lane-off` and `not-due`. Its model job runs `/improvement:find` unattended with `/architecture:improve deepening --unattended` inline and holds no write token, and its `file-architecture-findings` slot (`mutate-tracker`) files the verified candidates on the lanes App token, each with exactly one `source: architecture-improve` label.
- `own-agents.hold-sources` in `admission-rules.json` lists `source: <producer>` labels whose own-agent filings admission refuses for a listed human with a stated reason; it ships holding `source: architecture-improve`, and a missing key reads as an empty list.
