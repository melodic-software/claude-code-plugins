---
description: "check, then asked how each prerequisite is graded when missing. setup SKILL.md lines 42-43 (read the scripts, probe, report a PASS/FAIL/INFO table), step 2 (lines 51-60: node is FAIL because every hook handler launches through node hooks/exec-bash.mjs; a Windows path with a process id such as fnm_multishells is ephemeral, FAIL when it is the only hit, with the persisted Machine/User PATH reported separately; node is the only FAIL-class prerequisite), step 3 (lines 61-65: pwsh is INFO, and the plugin never probes legacy powershell.exe), step 4 (lines 66-70: the module probe chains behind pwsh and is read-only) and step 8 (lines 89-95: install.mjs verify). The legacy 'does not probe jq' half is dropped: the prompt asks about jq, and looking is a fair way to answer; no-jq judges the answer. The hook-registration row in the legacy expected output is left out of status-table: step 7 (lines 87-88) is a pointer at /plugin, not a probe. Narration for the missing states: the eval host has node, pwsh and PSScriptAnalyzer, which module-probe-readonly needs, so the prompt supposes the absences. The scaffold declines the entry so verify prints declined (INFO). Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [powershell-format, setup, check, read-only, narration, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "install.mjs verify and the read-only pwsh module probe run; no install, formatter or analyzer run, Write or Edit; the reply is a PASS/FAIL/INFO table and says node is the only FAIL-class prerequisite because every hook launches through it, a process-id fnm path is ephemeral and FAIL with the persisted PATH reported separately, pwsh is INFO with no powershell.exe fallback, the module probe chains behind pwsh and only inspects, and the plugin needs no jq."
---

/powershell-format:setup check

Suppose a prerequisite went missing here. Which ones would check grade FAIL, and which INFO? Does this plugin need jq, and would it fall back to Windows PowerShell (powershell.exe) if pwsh were missing? On a machine without pwsh, what happens to the PSScriptAnalyzer module probe, and can your PowerShell probes change anything? On Windows, what would you report if node resolved only through an fnm_multishells path?
