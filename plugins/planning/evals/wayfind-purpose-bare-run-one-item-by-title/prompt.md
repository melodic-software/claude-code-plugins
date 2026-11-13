---
description: "Purpose case for the before/after comparison: measures the outcome the replaced guidance served. P6: a bare call with an open map goes to work (now it lists the frontier, recommends one, waits)."
tags: [wayfind, wayfind-charting, purpose-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The session resolves at most one item and names items by title."
---

/planning:wayfind (interactive session; one open map exists, 'Map: billing overhaul' (#200), with frontier items 'Choose the billing aggregate' (#42), 'Pick the payment-provider adapter' (#43) and 'Decide invoice numbering' (#44))

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply.)
