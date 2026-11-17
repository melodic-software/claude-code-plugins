---
description: "check, then asked how each prerequisite is graded when missing. setup SKILL.md check: step 2 (node is FAIL because every hook handler launches through node hooks/exec-bash.mjs; a Windows path with a process id such as fnm_multishells is ephemeral, FAIL when it is the only hit, with the persisted Machine/User PATH reported separately), step 3 (the --resolve rows: an adapter row whose tool is not found is FAIL, a none row is INFO; the plugin never probes legacy powershell.exe), step 4 (the module probe runs only when a row found pwsh, is read-only, and is FAIL while a row resolved to the adapter) and step 9 (install.mjs verify). The scaffold's settings file opts the adapter in, so a missing pwsh or module is FAIL here and INFO only where no settings file is. The prompt asks about jq, and looking is a fair way to answer; no-jq judges the answer. Narration for the missing states: the eval host has node, pwsh and PSScriptAnalyzer, which module-probe-readonly needs, so the prompt supposes the absences. The scaffold declines both entries so verify prints declined (INFO). Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [powershell-format, setup, check, read-only, narration, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "The node probe, install.mjs verify and the read-only pwsh module probe run; no install, formatter or analyzer run, Write or Edit; the reply is a PASS/FAIL/INFO table and says node is FAIL everywhere because every hook launches through it, a process-id fnm path is ephemeral and FAIL with the persisted PATH reported separately, a missing pwsh or module is FAIL here because the settings file opts the adapter in (INFO without one), there is no powershell.exe fallback, the module probe needs pwsh found and only inspects, and the plugin needs no jq."
---

/powershell-format:setup check

Suppose a prerequisite went missing here. Which ones would check grade FAIL, and which INFO? Does this plugin need jq, and would it fall back to Windows PowerShell (powershell.exe) if pwsh were missing? On a machine without pwsh, what happens to the PSScriptAnalyzer module probe, and can your PowerShell probes change anything? On Windows, what would you report if node resolved only through an fnm_multishells path?
