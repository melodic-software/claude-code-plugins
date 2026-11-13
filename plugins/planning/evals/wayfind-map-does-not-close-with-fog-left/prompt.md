---
description: "wayfind evals.json case 29, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The map does not close while Not-yet-specified holds a bullet. The skill offers the ways out: chart it as an item if it can now be phrased, move it into a mop-up interview item, or have the user rule it out of scope, which moves it to Out-of-scope with the reason. It posts no closing comment and does not close the map in this turn."
---

/planning:wayfind work 'Map: billing overhaul' (#200). Every decision item is closed and the frontier is empty, but Not-yet-specified still has one bullet: '**Tax display**: something about how taxes show on invoices feels unsettled'. Close the map.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read this skill's own files with the Read tool, not Bash.)
