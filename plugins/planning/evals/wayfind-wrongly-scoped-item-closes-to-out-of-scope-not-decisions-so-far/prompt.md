---
description: "wayfind evals.json case 8, run as a plugin-eval case for the before/after comparison (loss-set)."
tags: [wayfind, wayfind-charting, loss-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The item is wrongly scoped: add one Out-of-scope line on the map that links the item first, then close it, and do not add a Decisions-so-far pointer. Fog stays in Not-yet-specified and is not moved into Out-of-scope."
---

/planning:wayfind work #200 — the claimed frontier item is #51 'Should we also rewrite the mobile app?', labeled wayfind: interview. Working it, we realize the rewrite is explicitly out of this effort's scope (web billing only). Close it out.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read this skill's own files with the Read tool, not Bash.)
