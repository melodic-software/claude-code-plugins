---
bump: minor
---

### Added

- A lane section takes `every-days` (an integer of at least 1, default 1): how many days a scheduled lane with a cadence gate waits, counted from its last run whose `Scan` job succeeded.
- The `maintenance-scan-architecture` lane, shipped with `enabled: false`. Its no-model gate job stops a daily or dispatched run as `lane-off`, `at-cap` (the open `source: architecture-improve` issues reach `find_open_item_cap`, default 5, from the improvement config cascade), `not-due` (fewer than `every-days` days since the last run whose `Scan` job succeeded) or `no-merges`; `lane-off`, `reads-unconfined` and a cap of 0 stop it before any API read, and a dispatch's `force` input skips only `lane-off` and `not-due`. `reads-unconfined` stops every run until the gate step sets `READS_CONFINED=true`, which waits on melodic-software/ci-workflows#1241 letting the legs block reads outside the checkout. Its model legs run `/improvement:find` unattended with `/architecture:improve deepening --unattended` inline, sandboxed, with named Bash commands only and no write token. Its `Scan` job drops any candidate naming a security defect or shaped like an issue another script trusts, and `File Findings`, only while the lane is on, files the rest on the job's own `GITHUB_TOKEN` (`issues: write`), each with exactly one `source: architecture-improve` label. The lane has no slot and no broker grant.
- `own-agents.hold-sources` in `admission-rules.json` lists `source: <producer>` labels whose issues admission refuses for a listed human with a stated reason, whoever filed them; it ships holding `source: architecture-improve`, and a missing key reads as an empty list.
