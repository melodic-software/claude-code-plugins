---
description: "check in a repository with a powershell record (fix-cmd and lint-cmd) and no PSScriptAnalyzerSettings.psd1. setup SKILL.md check step 3: both --resolve rows are none (INFO unresolved, the opt-out by design) and their detail says the record is not run by hooks; the hooks run only the shipped PSScriptAnalyzer adapter where a settings file opts it in, and the record runs only through /toolchain:lint and /toolchain:check, on request. The file_exists grader catches a settings file written. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [powershell-format, setup, check, read-only, no-network, record]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No file written, no Write or Edit. Both concerns unresolved INFO; the hooks never run the record's commands, only the shipped adapter where a settings file opts in; /toolchain:lint and /toolchain:check run the record on request."
---

/powershell-format:setup check

We put our format and lint commands in .claude/ecosystems/powershell.yaml. Why doesn't the commit hook run them?
