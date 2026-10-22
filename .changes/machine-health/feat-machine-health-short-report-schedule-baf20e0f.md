---
bump: minor
---

### Added

- Each audit run ends with a short report of at most 12 lines, printed by `scripts/windows/Format-ShortReport.ps1` from `state/latest.json`: host and run id, elevation, severity counts and the change since the prior run, the worst three CRIT or WARN summaries, the intruder headline (Defender detections, exposed unsigned or user-writable listeners, unexpected path exclusions, each "not read" when its source was not read), the largest unmuted folder, and the report and decision-page paths. Its first line is always `machine-health checkup <host> <run_id>`, and every machine-derived string is collapsed to one line.
- `/machine-health:audit --scheduled` marks an unattended run: `top-processes` samples for 60 seconds, the elevated pass is never offered, discovery only proposes checks in the report and `TODO.md` (it authors and registers none), and the short report is the whole final message.
- `/machine-health:setup schedule` creates the monthly checkup, only on the owner's yes: a Claude Desktop scheduled task (Custom cron `0 9 1 * *`, Auto or Manual plus one Run now), or a Task Scheduler task running a wrapper copied to `<StateBase>/scheduler/monthly-run.ps1`. The wrapper runs `claude -p "/machine-health:audit on-demand --scheduled"` in dontAsk mode with only the audit's tools (no web tools, no MCP servers) under a time limit, and writes `<StateBase>/logs/monthly-run-<runStamp>.status.json`, which counts the run ok only when claude exits 0, reports no error, opens its result with the short report's first line naming this run, and leaves a newer `latest.json`. Setup refuses the fallback for a synced or `--plugin-dir` state folder.
- Setup `check` reports the newest monthly-run status file, failing it when it is more than 35 days old, and notes a copied wrapper that differs from the shipped one.
- `state/latest.json` records the run's `run_stamp`, `report_path`, `page_path` and `cadence_deferred_count`.

### Changed

- The audit skill runs the orchestrator as a background command, and skips discovery writes when the state folder sits under a cloud sync root.

### Fixed

- Report, decision-page and battery-report file names use the Gregorian calendar whatever the current culture.
