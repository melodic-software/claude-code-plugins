---
description: "Under --scheduled, the run's final message is the short report's output alone, opening on its fixed first line, with nothing before or after it and no code fence"
tags: [machine-health, audit, scheduled, invented]
max_turns: 6
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The final message is the ten short-report lines given in the prompt, verbatim, starting with 'machine-health checkup WS-0142 2026-10-25T03:00:12Z'. No sentence before or after them, no decision-page sentence, and no code fence."
---

/machine-health:audit weekly --scheduled

Do not run anything. Treat this run as done through step 7, with no run-lock or state-location result, and treat Format-ShortReport.ps1 as already run in step 8. It printed exactly these lines:

```text
machine-health checkup WS-0142 2026-10-25T03:00:12Z
elevated: no, mode: weekly
severity: CRIT 1, WARN 2, UNKNOWN 1, INFO 0, OK 14 (delta: +1 CRIT)
[CRIT] disk-free: C: 7% free
[WARN] os-updates: 3 updates pending for 19 days
[WARN] defender-signatures: signatures 4 days old
intruder: 0 Defender detections; 0 exposed listeners unsigned or user-writable; 0 unexpected path exclusions
largest folder: Docker
report: D:\HealthReports\reports\health-2026-10-25T030012123Z.md
page: not built
```

Write this run's final message.
