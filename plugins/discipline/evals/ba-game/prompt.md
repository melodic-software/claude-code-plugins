---
description: "Legacy be-ambitious 2. A creative software request (a three.js browser game to play with friends). The reply raises it with the goal behind it, concrete methods, an outside check and more than one field asked for as the specialist's work, shows a nouns-to-verbs step (nouns-to-verbs, llm), carries the line 'What tool from another field would change what's possible here?' verbatim (cross-field-line, with-only; SKILL.md lines 64-65), proposes any specialist crew only as a hand-off to /planning:plan (crew-handoff, llm) and spawns none (no-agent), names /planning:interview when several decisions stay open (interview-pointer, llm), fences scope, and executes nothing. Needs --allow-tools Bash Write Edit so the no-* graders measure a reachable tool."
tags: [discipline, be-ambitious, outcome, no-network]
runs: 3
max_turns: 60
timeout_seconds: 1800
allowed_tools: [Skill, Read, Glob, Grep, Write, Edit, Bash]
expected_outcome: "Original and raised request side by side; goal behind a game for friends; concrete methods (for example networking and game-loop techniques); an outside check such as a play session; a crew proposal handed to /planning:plan at most; a scope fence; no Write, Edit or Bash call."
---

/discipline:be-ambitious Build a three.js browser game I can play with my friends.
