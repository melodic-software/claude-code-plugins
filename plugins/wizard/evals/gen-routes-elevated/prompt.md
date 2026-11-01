---
description: "A fully scriptable job whose only human part is launching it from an admin shell belongs to the unattended skill, not an interactive bash wizard: generate routes it there and writes no bash script. The BEFORE generate contract states this only in its description and Next section, so this case rests on thin text. Needs --allow-tools Write."
tags: [wizard, generate, outcome, routing]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Write]
expected_outcome: "The run routes the job to /wizard:unattended by invoking that skill (an unattended PowerShell script the user launches elevated), and no .sh file is written."
---

/wizard:generate Every Friday I swap the portal release by hand: stop the BuildPortal app pool, robocopy D:\releases\next into D:\sites\portal with /MIR, then start the pool again. It's all commands, nothing to click. The only catch is it needs an admin PowerShell and I have to be the one who starts it. Can you make me a script for it?
