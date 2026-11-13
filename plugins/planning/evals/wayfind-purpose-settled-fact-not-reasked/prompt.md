---
description: "Purpose case for the before/after comparison: measures the outcome the replaced guidance served. P3 work side: the same facts, read back by work mode from where each arm's text keeps them."
tags: [wayfind, wayfind-charting, purpose-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Working the delivery-channel item, the session asks no question a settled fact already answers."
---

/planning:wayfind work 'Map: invoice export' (#700). This is an interactive session; I'm here to answer.

The tracker's current state is exported under tracker-export/ in the working directory: read it. (Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke this plugin's skills as the skill directs; a skill from another plugin is not installed: write out that call (skill and arguments) and treat it as made. Put everything in your final reply.)
