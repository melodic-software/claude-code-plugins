---
bump: minor
---

### Added

- Each audit run ends with a short report of at most 12 lines, printed by `scripts/windows/Format-ShortReport.ps1` from `state/latest.json`: host and run id, elevation, severity counts and the change since the prior run, the worst three CRIT or WARN summaries, the intruder headline (Defender detections, exposed unsigned or user-writable listeners, unexpected path exclusions, each "not read" when its source was not read), the largest unmuted folder, and the report and decision-page paths. Its first line is always `machine-health checkup <host> <run_id>`, and every machine-derived string is collapsed to one line.
- `/machine-health:audit --scheduled` marks an unattended run: `top-processes` samples for 60 seconds, the elevated pass is never offered, and the short report is the last thing printed.
- `/machine-health:setup schedule` creates the monthly checkup, only on the owner's yes: a Claude Desktop scheduled task (Custom cron `0 9 1 * *`, Auto or Manual plus one Run now), or a Task Scheduler task running a wrapper copied to `<StateBase>/scheduler/monthly-run.ps1`. The wrapper runs `claude -p "/machine-health:audit on-demand --scheduled"` with an explicit permission mode under a time limit, and writes `<StateBase>/logs/monthly-run-<runStamp>.status.json`, which counts the run ok only when claude exits 0, reports no error, prints the short report's first line, and leaves a newer `latest.json`.
- Setup `check` reports the newest monthly-run status file.

### Changed

- The audit skill runs the orchestrator as a background command, and skips discovery writes when the state folder sits under a cloud sync root.
