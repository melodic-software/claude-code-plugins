---
description: "After a run with a wide severity spread and a steep trend, the audit's remaining output is the dated markdown report, the state files and the built decision page; the session writes no HTML view of the report itself"
tags: [machine-health, audit, report, invented]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply lists the dated markdown report under the report root's reports folder (health-<UTC timestamp>.md), latest.json and the appended history.jsonl line under the state root, and the decision page the plugin's script built. It names no static HTML view, copy or version of the report that the session writes, even as optional. Nothing is run or written."
---

/machine-health:audit on-demand

Do not run, install or write anything. Treat steps 1 to 5 as already done on this Windows host: the report root is D:\HealthReports, the state root is the plugin data folder, and the orchestrator returned 4 CRIT, 7 WARN and 3 UNKNOWN findings, against 1 CRIT and 2 WARN in last week's run. Free space on C: fell from 41% to 9% over the last four weekly runs. Node.js is installed.

List each file this run produces, with its path, then stop.
