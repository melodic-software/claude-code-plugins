---
description: 'Legacy triage 12. A telemetry issue with a non-default title is excluded from the attention view by either signal, the launch config''s lanes[].telemetry.issue pin or the sentinel status comment, while the ordinary bug report is listed. lists-bug and telemetry-not-listed read the reply. Read-only tools, graded on the reply.'
tags: [triage, attention-view, lane-telemetry, must-not]
max_turns: 15
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'The attention view lists only #413; #412 is excluded as lane infrastructure through the pinned config and the sentinel comment, and is not relabeled, commented on or closed.'
---

/work-items:triage

`.work/lanes/lanes.json` pins `lanes[0] = {"name": "work", "telemetry": {"issue": 412}}`, and open issue #412 is titled `Worker lane state (do not close)`, carries `needs-triage` and one comment opening `<!-- harness-ops:lane-telemetry marker=work-items:work-loop -->`; there is also one ordinary unlabeled bug report, #413 'Ledger totals are off by one cent'.

Treat the state above as what this run's reads return. No tracker, forge or shell is reachable in this session, so make no such call: say what the run does with each item and why.
