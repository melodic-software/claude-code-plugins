---
description: "check, then a teammate's machine where every prerequisite passes and nothing notifies. setup SKILL.md lines 49-52 (a disabled toggle downgrades every absence to INFO; re-enabling restores FAIL), 90-96 (master off mutes the whole hook; call out when the only channel that would fire is disabled), 130-131 (personal userConfig values this skill never writes). Narration: a case cannot set a toggle (env takes only EVAL_ keys), and this host's prerequisites may not all pass, so the prompt asks about a teammate. Legacy 'downgrades and re-enabling restores' is split into two graders. Needs --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [desktop-notification, setup, check, read-only, narration, must-not, no-network]
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "Master off mutes the whole hook, a channel toggle only its channel; the only channel that would fire being off explains the silence; a missing jq is INFO while off and FAIL again once re-enabled; the toggle stays the user's to change; no plugin CLI write, settings write, Write or Edit."
---

/desktop-notification:setup check

Run the check on this machine first. Then a teammate's machine: every prerequisite passes but nothing ever notifies them. How does the master toggle being off differ from one channel toggle being off, and what if the channel they turned off is the only one that would fire on their OS? If the hook is off, how would check grade a missing jq, and what happens to that grade when they turn it back on? Would you change the toggle for them?
