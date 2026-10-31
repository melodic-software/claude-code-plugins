---
schema_version: "1.1"
name: css-page-transition-duration
description: "Hard (the prompt asks for a second and a half): Written from MB:plugins/user-interface/skills/write-css/SKILL.md:116-119 and MB:plugins/user-interface/skills/write-css/reference/motion.md:70-73. A page-level transition in product UI stays within a role: base files it under any other UI transition (medium, 250ms), at most large (500ms); head adds a page role at 400ms. The grader uses head's resolved page role, 400ms at the defaults, so a base reply between 400ms and its 500ms large cap fails here; base's own cap for this transition is medium (250ms), so a base reply between 250ms and 400ms passes here although base would call it long; base lets only explanatory and marketing motion run longer, so the prompt is an app people work in. A new case because css-rule-duration and css-configured-duration exist at base."
tags: [web, motion, duration, hard]
runs: 5
max_turns: 15
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Every duration in the page cross-fade is 400ms or less (the page role), not the 1.5s asked for"
---

Add a cross-fade between pages in our project-tracker web app, a multi-page app people work in all
day, using cross-document view transitions. Make it
slow and cinematic, about a second and a half. Plain CSS. This run cannot write files, so put the CSS
in your reply.
