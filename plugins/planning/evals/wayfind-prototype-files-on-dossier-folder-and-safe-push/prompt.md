---
description: "wayfind evals.json case 28, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The prototype's files go in #504's own folder on the map's single dossier branch. The push is fetch, rebase, then a plain push without force, retried after a fresh fetch and rebase if rejected; it needs no force because the other session writes only its own item's folder. The verdict (each pass check passed) goes in the resolution comment with a link to the folder; then the pointer is added and the item closed."
---

/planning:wayfind work 'Map: notification vendor' (#500). The claimed prototype item 'Prove Knock sends email and in-app from one call' (#504) is done: the pressure-test passed all checks. Another session is writing research findings to the same map's dossier branch right now. Save the prototype files and close the item.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read this skill's own files with the Read tool, not Bash.)
