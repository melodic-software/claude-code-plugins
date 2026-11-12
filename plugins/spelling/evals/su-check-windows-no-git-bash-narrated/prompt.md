---
description: "A teammate's native Windows failure, narrated, because this host cannot stage a missing Git Bash and SKILL.md's disable-model-invocation (line 5) needs the slash command, which loads here. setup SKILL.md lines 50-53: shell: bash without bash fails the invocation before any command runs, so step 1 reports only a version and never diagnoses the missing Git Bash, and the README Requirements section carries the answer; README lines 49-50 name Git for Windows. Dropped legacy expectation: 'does not run any probe', because the skill loads on this host and check legitimately probes it; writes and installs stay guarded by the must-nots, which also cover the legacy 'edit settings'. The legacy prompt said the skill would not load for the asker, which the loaded skill contradicts, so the failure moves to a teammate's machine. The scaffold declines the entry so verify prints declined. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [spelling, setup, check, narration, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No install, spell-check run, install.mjs write verb, plugin CLI write, Write or Edit; the reply says the cause is the missing Git Bash, the skill fails before any command runs so the Bash version step cannot diagnose it, the fix is Git for Windows per the README Requirements section, and the teammate reruns /spelling:setup afterwards."
---

/spelling:setup check

A teammate on native Windows runs this same command and it fails with: Skill setup requires bash (`shell: bash` in frontmatter) but Git Bash was not found. Is that a plugin bug, or typos or jq missing? Why doesn't check's Bash version step catch it for them, what should they install, where is that written down, and what should they do after installing it?
