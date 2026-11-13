---
description: "wayfind evals.json case 15, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "With no item named, work takes the first frontier item in creation order, #42. wayfind_hitl_concurrency resolves to 1 from the default and counts per person; #41, assigned to this same person, already holds that slot, so #42 is skipped; the skill claims #43 instead and reports that the HITL slot is held by 'Decide invoice numbering' (#41)."
---

/planning:wayfind work 'Map: billing overhaul' (#200). The frontier, in creation order: 'Choose the billing aggregate' (#42, wayfind: interview, needs-human), 'Measure current invoice volume' (#43, wayfind: task, no needs-human). I already hold 'Decide invoice numbering' (#41, needs-human, assigned to me) from another session. No setting is configured.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply.)
