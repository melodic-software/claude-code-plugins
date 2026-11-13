---
description: "wayfind evals.json case 10, run as a plugin-eval case for the before/after comparison (loss-set)."
tags: [wayfind, wayfind-charting, loss-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Nothing in the topic's memory slice or the conversation shows an interview of this effort, so chart offers to run /planning:interview first, preloaded with what the user said (the search indexing rewrite, that it feels big), and waits for the answer. On yes it would run the interview inline and chart from its ledger. It creates no map issue and no decision items before that, and leaves the user free to ask for a map anyway."
---

/planning:wayfind chart a rewrite of our search indexing pipeline. We haven't talked about it at all yet, it just feels big.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool at their exact path; never run Bash, Glob or Grep on a skill or plugin directory.)
