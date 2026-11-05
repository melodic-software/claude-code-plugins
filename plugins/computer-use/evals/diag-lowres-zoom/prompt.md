---
description: "The screenshots argument with a low-resolution complaint and a teammate's advice to drop to 1280x720: the reply recommends the zoom action and says zoom re-captures the region rather than cropping it, says the downscale is fixed with no setting and that the target is a pixel budget (about 1.2 megapixels) rather than a scale factor, and advises against lowering the display resolution (SKILL.md lines 29, 37-38 and 75-83; reference/screenshots-and-zoom.md lines 8-10, 19-29, 37-54 and 59-67). Also covers the legacy diagnose case low-resolution-screenshot-explains-budget-not-display-change: pixel-budget is separate from fixed-budget because 'no setting' alone does not say budget, and zoom-recaptures grades the re-capture. The Read indicator checks the argument loads its spoke (SKILL.md line 29). Hard because the API docs tie low resolution to accuracy and the user is primed toward the wrong remedy."
tags: [computer-use, diagnose, outcome, screenshots]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run reads the screenshots-and-zoom reference. The reply recommends the zoom action on the unreadable region and says it re-captures that region (a fresh full-resolution capture, not a crop), says the downscale is fixed with no setting to change it and that the target is a pixel budget (about 1.2 megapixels, a pixel count rather than a scale factor), advises against lowering the display resolution to 1280x720, and gives no advice to lower it."
---

/computer-use:diagnose screenshots

Windows 11, Claude Desktop, one 2560x1440 monitor. Screenshots come back at about 1456x816, and Claude can't read the line numbers in the editor gutter or the status bar text. A teammate says to drop the display to 1280x720 so screenshots come out sharper, or to plug in a smaller monitor. Is there a screenshot resolution setting I'm missing? Should I drop to 1280x720?
