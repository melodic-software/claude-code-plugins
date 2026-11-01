---
description: "A motion bug the reporter describes only in words: the report asks for the frame state (a frame-state export, or the property values, timing and progress at the frame that looks wrong, with the playback speed) instead of settling for stills or a video, and invents no animation values"
tags: [bugs, write, motion, outcome]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "A bug report, or one targeted question, that asks the reporter for the frame state of the jump (a frame-state export such as one from /app-control:drive capture --kind animation, or each animating property's value, from and to, duration, easing and progress at the frame where it jumps, plus the playback speed it was seen at), or lists that evidence under Notes as needed; it states no duration, easing or opacity value the reporter did not give."
---

/bugs:write The settings drawer in `apps/web/src/components/SettingsDrawer.tsx` jumps when I close
it while it is still opening: the panel snaps to fully open and then slides out. It happens every
time I hit the close button right after opening it. I don't have a recording. Write this up as a
bug report.
