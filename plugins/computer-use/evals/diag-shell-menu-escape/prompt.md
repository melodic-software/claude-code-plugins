---
description: "Legacy diagnose case shell-menu-escape-distinguished-from-in-app-menu, slash-invoked with the quirks argument on Windows 11: a File Explorer context menu stays open after two synthesized Escapes, and the user asks how to close it and why Escape fails. The reply says to dismiss it with a left-click on empty space, distinguishes shell-owned menus from in-app menus, which do close on Escape, and does not present a mechanism for the Escape failure as known (SKILL.md lines 30, 42 and 46-50; reference/windows-quirks.md lines 11-30). The Read indicator checks the argument loads the Windows quirks file. The legacy 'does not repeat escape' expectation is not a tool grader: no run has a computer-use tool to send keys with. No Bash grant, so the run cannot read the sandbox's own OS and skip the Windows file. Hard because the user asks why, inviting an invented explanation, and Escape is the natural retry."
tags: [computer-use, diagnose, outcome, quirks, windows]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run reads the Windows quirks reference. The reply says to close the menu with a left-click on an empty area, says shell-owned menus such as File Explorer's context menu ignore a synthesized Escape while in-app menus (such as Notepad's) close on it, and does not state a cause for the Escape failure as established; saying the mechanism is unknown is fine."
---

/computer-use:diagnose quirks

Windows 11, Claude Desktop. Claude right-clicked a file in File Explorer and the context menu opened. It sent escape to close it and the menu stayed up; it sent escape again and nothing changed. How should it close the menu, and why is Escape failing?
