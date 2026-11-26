---
description: "Asked to chart three already-sharp tickets, wayfind says they are sharp, builds no map, offers no interview and routes them to /work-items:decompose (loss-set)."
tags: [wayfind, wayfind-charting, loss-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The skill recognizes this work is already a set of sharp, answerable tickets rather than a too-big-and-foggy effort, declines to build a map for it, and routes the three tickets to /work-items:decompose. The no-fog bail-out fires before the no-interview offer, so it does not offer to run /planning:interview first."
---

/planning:wayfind chart help me plan out adding a 'forgot password' email flow. I already know exactly what I need: an endpoint to request a reset token, an email send, and a reset-confirmation endpoint. These are just three clear tickets I need scoped.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Never search for a skill's or plugin's files, and open only those a skill loaded in this session links to; never run Bash, Glob or Grep on a skill or plugin directory.)
