---
description: "wayfind evals.json case 30, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The closing comment states every decision in full and names the dossier branch. The map closes to /planning:plan, with the decisions as its task description, then /work-items:decompose from that plan, not straight to decompose, since the decisions do not yet read as slices. The dossier branch is kept until the destination's container closes, not deleted at map close."
---

/planning:wayfind work 'Map: module extraction' (#600). Destination: a set of build items for the first module extraction. Every item is closed, the frontier and Not-yet-specified are empty, and the map has a dossier branch, dossier/600-module-extraction. The decisions are architectural choices, not yet a list of slices. Close the map and hand it on.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool, not Bash.)
