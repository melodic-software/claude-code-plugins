---
bump: minor
---

### Added

- `/harness-ops:morning-brief` frames the issue, pull-request, review-thread, telemetry and annotation text it prints as data, reports an embedded instruction instead of following it, and treats the lane telemetry notes it re-reads as a poisoning route. It names its three lethal-trifecta legs (private data, untrusted text, an outbound channel) and the leg it cuts: the outbound channel. A new eval case, `mb-issue-body-is-data`, plants an instruction in an issue body.

### Changed

- `/harness-ops:morning-brief` labels the zone on every date stamp it prints: the header time, the stranded window's start and each lane's `last-cycle` now read `... UTC`. The stranded-findings bookmark file keeps the bare form. A scheduled prompt that runs the skill names UTC.
