---
tags: ['reach']
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: 'Uses row R4: resolves the distro name from wsl.exe -l -q rather than guessing, then wsl.exe -d <distro> --cd /tmp --exec <shell> -lc (--exec, not --) with claude -p "<prompt>" < /dev/null inside single quotes. Gives the prompt the whole task and a stop condition. Escapes any apostrophe by doubling it, which is the pwsh rule; notes that Git Bash (a native-Windows Claude''s Bash tool) needs ''\'''' instead, because doubling drops the apostrophe there. Prefers WSL as the agent lane since the repos and toolchain live there.'
---

From a PowerShell window on the laptop, ask the WSL side of the laptop to run the test suite in my repo and report back. Give me the exact command to run; don't run it yourself.
