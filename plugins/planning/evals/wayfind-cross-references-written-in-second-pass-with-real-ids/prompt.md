---
description: "wayfind evals.json case 14, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Chart creates both items first with no reference to each other in their bodies, then in a second pass, once both have real ids, wires 'Choose the delivery channel' as blocked by 'Pick the export format' and edits its body to link the format item by absolute URL. It never writes a guessed or placeholder issue number."
---

/planning:wayfind chart — we interviewed the billing-export feature earlier in this session and it outgrew one sitting; destination confirmed: a PRD for it. I said yes to the proposed map. Create the decision items: 'Pick the export format' and 'Choose the delivery channel', where the delivery-channel item depends on the format decision and its body should point at it. Neither item exists on the tracker yet.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool, not Bash.)
