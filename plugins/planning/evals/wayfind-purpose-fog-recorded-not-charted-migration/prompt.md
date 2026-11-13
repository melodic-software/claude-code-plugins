---
description: "Purpose case for the before/after comparison: measures the outcome the replaced guidance served. P4: fog as prose in Not-yet-specified (now one labeled bullet per uncertainty)."
tags: [wayfind, wayfind-charting, purpose-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The cross-module-transactions worry is recorded under Not-yet-specified and is not charted as an item."
---

/planning:wayfind chart migrating our monolith to a modular architecture. We interviewed this earlier in the session and it outgrew one sitting. I confirm the destination: a set of build items for the first module extraction. I know some pieces: we've agreed the database can't be split yet (that's out of scope for now), and we need to decide whether to go strangler-fig or big-bang (that's answerable, if painful). But I genuinely don't know yet how we'd handle cross-module transactions — I can't even phrase that as a real question.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool at their exact path; never run Bash, Glob or Grep on a skill or plugin directory.)
