---
description: "wayfind evals.json case 13, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Before any map issue or decision item exists, chart asks what done looks like: it states the destination in one or two lines (what finishing the map produces, one bounded outcome of a named kind, recommending a PRD for this coding effort) and asks the user to confirm it. Only after that does it propose the map, with auth scheme, rate-limit model and versioning policy as decision items and partner tiers as a Not-yet-specified bullet, and it creates nothing before the user's yes on that proposal."
---

/planning:wayfind chart the partner-API v2 effort. We interviewed it earlier in this session and it outgrew one sitting. The open questions are auth scheme, rate-limit model and versioning policy, and nobody can yet say what 'partner tiers' should mean.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool, not Bash.)
