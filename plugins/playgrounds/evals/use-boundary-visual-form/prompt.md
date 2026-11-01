---
description: "Boundary near miss (SKILL.md lines 141-143 and the description's 'Not for choosing a visual form for conversation content'): the user wants the best static way to present tradeoffs they paste in, not a manipulable explorer whose output returns as a prompt. The skill must not fire, and the reply must not push the playground install. The only plugin skill loaded is this one, so the no-route grader tests quietness, not a competitor win."
tags: [playgrounds, use, outcome, near-miss]
max_turns: 10
timeout_seconds: 600
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "No playgrounds:use or playground Skill call, and the reply does not name `playground@claude-plugins-official`."
---

Here are the three caching strategies we compared: write-through (simple, slower writes, always consistent), write-back (fast writes, risk of loss on crash, complex), and cache-aside (app-managed, stale reads possible, easy to adopt). For the design review I need one static view that lets people compare them at a glance. Which format should I put this in? Lay it out for me.
