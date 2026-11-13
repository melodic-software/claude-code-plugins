---
description: "wayfind evals.json case 23, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "wayfind_hitl_concurrency resolves to 1 from the default and counts claims per person (assignee). Dana's claim on #41 does not count against this person, who holds no needs-human item, so the skill claims #42 and routes it to /planning:interview."
---

/planning:wayfind work 'Map: billing overhaul' (#200). The frontier, in creation order: 'Choose the billing aggregate' (#42, wayfind: interview, needs-human). My teammate Dana holds 'Decide invoice numbering' (#41, needs-human, assigned to Dana). I hold no item on this map. No setting is configured.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read this skill's own files with the Read tool, not Bash.)
