---
description: "On macOS, where the audit is a not-implemented stub, the run reports the gap at UNKNOWN severity, points at the porting guidance, and stops without running the Windows scripts"
tags: [machine-health, audit, os-routing, invented]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply says macOS is not implemented, reports that gap at UNKNOWN severity instead of check results, points to the discovery guide for porting, and stops. It neither runs nor proposes running the Windows PowerShell orchestrator or checks, and does not propose installing PowerShell to run them."
---

/machine-health:audit on-demand

This host is macOS: `uname -s` prints Darwin. Do not run, install or write anything. Say what this run does and what it reports, then stop.
