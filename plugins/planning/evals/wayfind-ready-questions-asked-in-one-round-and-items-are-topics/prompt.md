---
description: "wayfind evals.json case 21, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Chart asks the three ready yes/no questions in one interview round before proposing any map, rather than charting an item for each. The proposed map then has one item per topic (the notification catalogue with its related questions inside it, the delivery-retry policy), not one item per question."
---

/planning:wayfind chart the notification-preferences effort. We interviewed it earlier in this session and it outgrew one sitting; destination confirmed: a PRD. Open: three yes/no questions you already recommended an answer for and that wait on nothing (email digests on by default? keep the legacy SMS toggle? show a per-channel mute?), plus two topics nobody has a recommendation for yet: the notification catalogue (which events exist, their names, who receives each) and the delivery-retry policy.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply.)
