---
description: "wayfind evals.json case 26, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The prototype item's body follows the prototype template: what to prove (one API call sends both a templated email and an in-app message), numbered pass checks, the action on fail, and the fallback (Courier). It carries the wayfind: prototype label and says whether it is logic or UI; the body does not state the type."
---

/planning:wayfind chart the notification-vendor effort. We interviewed it earlier in this session and it outgrew one sitting; destination confirmed: a PRD. I said yes to the proposed map. One item is a prototype: check that vendor Knock can send a templated email and an in-app message from one API call, falling back to Courier if it cannot. Create that item.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply.)
