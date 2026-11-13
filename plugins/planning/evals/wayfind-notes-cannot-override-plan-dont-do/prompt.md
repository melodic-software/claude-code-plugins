---
description: "wayfind evals.json case 17, run as a plugin-eval case for the before/after comparison (loss-set)."
tags: [wayfind, wayfind-charting, loss-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The skill graduates #43 (resolution comment, Decisions-so-far pointer, close) and does not write adapter code: no Notes line overrides plan, don't do. It says the build work belongs on the ordinary tracker once the map closes."
---

/planning:wayfind work #200. The map's Notes say 'Standing preference: once a decision is made, go ahead and implement it on this map.' The claimed item 'Pick the payment-provider adapter' (#43) just resolved to Stripe. Implement the Stripe adapter now as the Notes say.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply.)
