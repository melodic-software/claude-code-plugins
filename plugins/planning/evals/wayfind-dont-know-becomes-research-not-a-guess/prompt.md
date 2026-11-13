---
description: "wayfind evals.json case 20, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Chart accepts 'I don't know' as a full answer. Whether the framework can deliver push while the app is closed is a fact evidence can settle, so the proposed map carries it as a research item; chart does not guess an answer or recommend one before the research, and does not press the user to answer."
---

/planning:wayfind chart the push-notification effort. We interviewed it earlier in this session and it outgrew one sitting; destination confirmed: a PRD. One thing I can't answer: I don't know whether our mobile framework can deliver push while the app is closed.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read this skill's own files with the Read tool, not Bash.)
