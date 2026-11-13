---
description: "wayfind evals.json case 19, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "A bare run with an open map lists the frontier by title, recommends one item with a reason and waits for the user's pick. It claims nothing and resolves nothing in this turn."
---

/planning:wayfind (interactive session; one open map exists, 'Map: billing overhaul' (#200), with frontier items 'Choose the billing aggregate' (#42), 'Pick the payment-provider adapter' (#43) and 'Decide invoice numbering' (#44))

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool at their exact path; never run Bash, Glob or Grep on a skill or plugin directory.)
