---
description: "wayfind evals.json case 4, run as a plugin-eval case for the before/after comparison (loss-set)."
tags: [wayfind, wayfind-charting, loss-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Chart mode treats the caller's unattended declaration as the signal and STOPS, reporting that charting needs a human in the loop, rather than fabricating a map on its own."
---

/planning:wayfind chart the customer-data-platform overhaul. (This is running as an unattended autonomous batch job — no human is available to respond.)

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read this skill's own files with the Read tool, not Bash.)
