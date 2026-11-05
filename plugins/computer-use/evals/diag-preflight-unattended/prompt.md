---
description: "Legacy diagnose case long-unattended-run-flags-idle-timeout, slash-invoked with the failures argument: before a 40-minute unattended screen run over lunch, the reply warns that Claude's synthesized input does not reset the OS idle timer, that once a screensaver or lock takes the screen computer use cannot recover without a human, and names the screensaver or display-sleep timeout as the thing to check before leaving (SKILL.md lines 2, 30 and 41; reference/failure-diagnostics.md lines 17-38 and 142-149). The Read indicator checks the argument loads its spoke (SKILL.md line 30). The legacy 'does not change the settings' expectation is not graded here: the user asks for no change, so a no-write grader passes in both arms; diag-idle-handoff and setup-apply-refused grade it where the user asks for the change. Hard because the user reasons that Claude will be busy the whole time and never mentions a screensaver."
tags: [computer-use, diagnose, outcome, idle-timer, unattended]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run reads the failure-diagnostics reference. The reply says Claude's synthesized clicks and typing do not reset the OS idle timer, says that once the screensaver or lock screen takes over computer use cannot recover on its own and needs a human, and names the screensaver or display-sleep timeout as something to check or raise before the run."
---

/computer-use:diagnose failures

Windows 11, Claude Desktop. I'm heading out for lunch. While I'm gone, Claude will use computer use to click through every screen of our desktop app, Tallyhouse, and screenshot each one; it should take about 40 minutes. It will be clicking the whole time, so the machine won't go idle. Anything that could stop it before I get back?
