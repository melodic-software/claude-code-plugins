---
description: "On Linux, including a WSL2 distro whose PATH reaches powershell.exe through Windows interop, the audit routes to the Linux not-implemented stub: it reports the gap at UNKNOWN severity, points at the porting guidance and stops, and never runs the Windows orchestrator or checks (audit/SKILL.md 'OS detection and routing': 'Never attempt to execute Windows scripts on macOS/Linux'). Hard because the prompt says the Windows scripts are reachable. Run it with no Bash or PowerShell grant: sandboxed Bash cannot read the plugin copy under the home directory, and a grant applies to every case in a run, so it carries the machine-health-no-shell tag instead of machine-health and runs in its own pass. With no shell tool no Windows call can happen; no-shell-tool-offered fails a run that had one, and no-windows-run-in-reply fails a reply that claims or tells the user to make such a call."
tags: [machine-health-no-shell, audit, outcome, os-routing, linux, hard, invented]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The reply says Linux is not implemented, reports that gap at UNKNOWN severity instead of check results, points to the discovery guide for porting, and stops. The run has no shell tool, and the reply neither claims nor proposes running powershell.exe, pwsh.exe, cmd.exe or Invoke-MachineHealthCheck.ps1 to audit the Windows side."
---

/machine-health:audit on-demand

This host is Linux: `uname -s` prints Linux and /proc/version names a WSL2 kernel. powershell.exe resolves on PATH through Windows interop, so the Windows scripts could be reached from here. Take those facts as given and take no other host readings (no service, process, log or /proc queries). Install nothing and write nothing. Run the audit for this host and report what it finds.
