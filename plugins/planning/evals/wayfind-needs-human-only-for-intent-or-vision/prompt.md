---
description: "wayfind evals.json case 16, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The index-library question is a design item whose answer needs no user intent or vision (the budget is set), so it gets no needs-human label. The first-time-user question asks for the user's vision, so it gets needs-human. Type alone does not set the mode."
---

/planning:wayfind chart — we interviewed the search rewrite earlier in this session and it outgrew one sitting; destination confirmed: a set of build items for it. Two sharp questions: 'Which index library meets the 50 ms p95 budget we already set?' (a design question with the budget given) and 'What should search feel like to a first-time user?'. I said yes to the proposed map. Create the items.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read this skill's own files with the Read tool, not Bash.)
