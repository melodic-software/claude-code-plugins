---
description: "wayfind evals.json case 7, run as a plugin-eval case for the before/after comparison (loss-set)."
tags: [wayfind, wayfind-charting, loss-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Work mode reports the frontier by item title, with the number as a link or suffix (for example 'Choose the billing aggregate' (#42)), never a wall of bare #42, #43, #44. It then picks one item, claims it, and routes by type rather than resolving all three inline."
---

/planning:wayfind work — the open map is #200 'Map: billing overhaul'. The frontier has three unblocked unassigned items: #42 'Choose the billing aggregate', #43 'Pick the payment-provider adapter', #44 'Decide invoice numbering'. Report the frontier and pick one.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool at their exact path; never run Bash, Glob or Grep on a skill or plugin directory.)
