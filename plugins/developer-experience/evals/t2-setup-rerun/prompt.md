---
description: "Scenario T2 (setup re-run) on the converged tarnquill fixture: setup apply on a repository already set up leaves AGENTS.md and docs/conventions/developer-experience.md byte for byte as seeded (items 1 and 2, graded on the files), with no Write or Edit call and no Bash call that writes or deletes a file through a redirect, cp, mv, rm, touch, mkdir, tee, sed -i or git rm, alone or inside a compound command. The scenario runs the plugin arm only; here the no-plugin arm gets the same slash prompt"
tags: [setup, t2]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Write, Edit, Bash, Skill]
expected_outcome: "setup check finds the pointer line current and the conventions file in place, reports what it cannot settle without the user (such as the CLI contract body that differs from the current default) and writes nothing"
---

/developer-experience:setup apply. I confirm the changes it shows.
