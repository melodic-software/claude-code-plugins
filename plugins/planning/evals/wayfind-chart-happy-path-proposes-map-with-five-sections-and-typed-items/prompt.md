---
description: "wayfind evals.json case 3, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Chart mode surveys the effort and proposes the whole map before creating anything on the tracker: a body with the five sections (Destination, Notes, Decisions-so-far, Not-yet-specified, Out-of-scope) and the items to create. The strangler-fig-vs-big-bang question is a typed decision item (sharp); the cross-module-transactions unknown is a labeled bullet under Not-yet-specified; the database-split exclusion is under Out-of-scope. It waits for the user's yes on that proposal, and says /planning:wayfind work follows once the map exists, rather than resolving decisions itself."
---

/planning:wayfind chart migrating our monolith to a modular architecture. We interviewed this earlier in the session and it outgrew one sitting. I confirm the destination: a set of build items for the first module extraction. I know some pieces: we've agreed the database can't be split yet (that's out of scope for now), and we need to decide whether to go strangler-fig or big-bang (that's answerable, if painful). But I genuinely don't know yet how we'd handle cross-module transactions — I can't even phrase that as a real question.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool at their exact path; never run Bash, Glob or Grep on a skill or plugin directory.)
