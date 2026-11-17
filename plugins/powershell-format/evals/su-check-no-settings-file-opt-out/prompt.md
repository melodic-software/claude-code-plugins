---
description: "check in a repository with a script and no settings file, asked whether the plugin is broken. setup SKILL.md Purpose (with no settings file, a missing pwsh, module or settings file is INFO, never FAIL), check step 3 (a none row: the hooks run only on a file a settings file governs, walking up from the file to the repo root and stopping at the closest one; absence is the opt-out, by design) and What this skill does not do (never writes the settings file). The scaffold declines both entries, so verify prints declined and the only verdict in question is the settings one. The file_exists grader catches a settings write by any tool. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [powershell-format, setup, check, read-only, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No settings file is written or offered; no install, formatter or analyzer run, Write or Edit; the reply says the plugin is not broken, the absence is INFO, the opt-out by design, the check walks up from the file to the repo root stopping at the closest settings file, and a missing pwsh or module is INFO too."
---

/powershell-format:setup check

We have no PSScriptAnalyzerSettings.psd1 and nothing is being formatted. Is the plugin broken? How does it decide which files it checks, and would a missing pwsh or PSScriptAnalyzer module be a FAIL too?
