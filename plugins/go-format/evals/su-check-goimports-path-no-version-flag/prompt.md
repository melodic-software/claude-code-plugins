---
description: "check, asked how goimports resolves, what version it is, and what a missing jq or goimports does. setup SKILL.md lines 53-54 (the table), step 2 (lines 63-64: jq FAIL, the batch hook does nothing) and step 4 (lines 70-74: PATH only; the resolved path and goimports -h's first line because there is no --version flag; absent is FAIL, the hook skips the files, the SessionStart probe reports it). Fixed: legacy 'visible once-per-session skip notice' for both tools is stale. The batch hook is silent (hooks/go-format.sh lines 49-50) and prerequisites.json declares both tools, so the SessionStart probe reports them. The goimports row is pre-computed at load (line 24), so PATH-only is graded on the reply; -h is a live call, so help-probe-ran is tool_used. Dropped: legacy expected_output 'one remediation line per FAIL', since the host has every tool and no row fails. Narration: the prompt supposes the absences. Needs goimports, jq and node on the host. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [go-format, setup, check, narration, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "goimports -h and install.mjs verify run; no goimports --version, install, formatter run, plugin CLI write, install.mjs write verb, Write or Edit; the reply grades a status table, says goimports resolves on PATH only, gives its resolved path and help line as the version signal, and says a missing jq makes the hook do nothing while a missing goimports makes it skip the files with the session-start probe reporting the absence."
---

/go-format:setup check

How does it find goimports: a per-repo install like a .venv, or something else? What version of goimports is this? If jq or goimports were missing, how would each be graded, what would stop working, and where else would I hear about it?
