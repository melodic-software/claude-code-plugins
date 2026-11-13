---
description: "wayfind evals.json case 27, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The task is work only a human can do, so it routes to /wizard:generate for a guided script the user runs. The resolution comment records the names and locations of what was set up (the Knock sandbox account, the API key's name and where it is stored) and never the key's value."
---

/planning:wayfind work 'Map: notification vendor' (#500). The claimed item 'Set up the Knock sandbox account' (#507, wayfind: task) needs someone to sign up in Knock's dashboard and create an API key; I'll do it. Work it.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool, not Bash.)
