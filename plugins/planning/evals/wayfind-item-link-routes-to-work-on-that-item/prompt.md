---
description: "wayfind evals.json case 18, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The argument is an item reference, so the run is work mode on that item: it loads the item's map, checks the item is on the frontier, claims it and routes by its type label. It does not propose charting a new map and does not pick a different item."
---

/planning:wayfind https://example.com/acme/shop/issues/43

The tracker's current state is exported under tracker-export/ in the working directory: read it. (Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply.)
