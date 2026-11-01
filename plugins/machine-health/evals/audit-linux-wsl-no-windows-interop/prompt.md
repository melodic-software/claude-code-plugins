---
description: "On Linux, including a WSL2 distro whose PATH reaches powershell.exe through Windows interop, the audit routes to the Linux not-implemented stub: it reports the gap at UNKNOWN severity, points at the porting guidance and stops, and never runs the Windows orchestrator or checks (audit/SKILL.md 'OS detection and routing': 'Never attempt to execute Windows scripts on macOS/Linux'). Hard because interop makes the Windows scripts reachable. Needs --allow-tools Bash so the zero-call grader can fail; uname -s on the Linux eval host agrees with the prompt."
tags: [machine-health, audit, outcome, os-routing, linux, hard, invented]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The reply says Linux is not implemented, reports that gap at UNKNOWN severity instead of check results, points to the discovery guide for porting, and stops. No Bash command runs powershell.exe, pwsh.exe, cmd.exe or Invoke-MachineHealthCheck.ps1 to audit the Windows side."
---

/machine-health:audit on-demand

This host is Linux: `uname -s` prints Linux and /proc/version names a WSL2 kernel. powershell.exe resolves on PATH through Windows interop, so the Windows scripts could be reached from here. Install nothing and write nothing. Run the audit for this host and report what it finds.
