---
description: "wayfind evals.json case 24, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "After graduating #42 and sweeping, work reports the closed item, its new Decisions-so-far line, that no new items were charted, and that #44 is now unblocked. It ends with one line: clear, then /planning:wayfind https://github.com/acme/shop/issues/44."
---

/planning:wayfind work 'Map: billing overhaul' (#200). The claimed item 'Choose the billing aggregate' (#42, https://github.com/acme/shop/issues/42) just resolved: one Invoice aggregate per tenant. That unblocks 'Decide invoice numbering' (#44, https://github.com/acme/shop/issues/44), which becomes the first frontier item; nothing new needs charting. Finish the item.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply.)
