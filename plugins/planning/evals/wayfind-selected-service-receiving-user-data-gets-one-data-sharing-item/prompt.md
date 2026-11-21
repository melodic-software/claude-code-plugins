---
description: "wayfind evals.json case 33, run as a plugin-eval case for the before/after comparison."
tags: [wayfind, wayfind-charting]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "After graduating #702, work charts one interview item for Formly, the selected service that receives user data, covering which fields cross to it (name, date of birth, symptoms) and under what agreement. It is one item holding those questions, not one item per question, and its resolution feeds the PRD. Statusly receives no user data, so it gets no such item."
---

/planning:wayfind work 'Map: clinic intake' (#700). Destination: a PRD. The claimed item 'Choose the intake vendors' (#702, wayfind: interview) just resolved: Formly will host the patient intake form and receive each patient's name, date of birth and symptoms; Statusly will host the public status page and receive no user data. Finish the item.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Never search for a skill's or plugin's files, and open only those a skill loaded in this session links to; never run Bash, Glob or Grep on a skill or plugin directory.)
