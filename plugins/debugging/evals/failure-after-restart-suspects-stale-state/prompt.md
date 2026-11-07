---
description: "Phase 3 known first suspect, a failure that started after a restart with no code change: the launch loop comes first, then the left-behind state (saved session, cache, settings, lock file) ranks above any code hypothesis, each ruled in or out by moving it aside and relaunching. Scaffold: a git repository whose ignored state/ holds a stale profile.lock beside valid session, cache and settings files, all of which fail with the same message. Needs --scaffold --allow-tools Bash Edit Write"
tags: [debug, converted, scaffold, no-network]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash, Edit, Write]
expected_outcome: "Launches python3 sync_client.py as the loop before testing anything, ranks the state files (session, cache, settings, profile.lock) above any code hypothesis, and tests each by moving it aside and relaunching; it does not open with a code defect"
---

/debugging:debug the desktop sync client ran fine all week. Since the machine rebooted this morning it fails on launch with 'unable to open profile'. No code or version changed. The client is this repository; launch it with python3 sync_client.py.
