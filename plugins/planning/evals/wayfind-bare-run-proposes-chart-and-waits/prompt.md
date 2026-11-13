---
description: "wayfind evals.json case 12, run as a plugin-eval case for the before/after comparison (loss-set)."
tags: [wayfind, wayfind-charting, loss-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "No open map exists for the topic, so the bare run resolves to chart. Because chart was not asked for by name, the skill proposes charting the warehouse-routing rework and waits for the user's yes before surveying, creating a map issue or creating decision items."
---

/planning:wayfind We interviewed the warehouse-routing rework earlier in this session and it kept opening more questions than it closed.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read this skill's own files with the Read tool, not Bash.)
