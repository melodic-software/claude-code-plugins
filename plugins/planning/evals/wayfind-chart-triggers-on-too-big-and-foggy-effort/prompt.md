---
description: "wayfind evals.json case 1, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Chart was asked for by name, so it proceeds without proposing first. The effort was already interviewed, so chart does not offer the interview again. The skill surveys the effort and runs every uncertainty through the fog test — sharp (phraseable, even if unanswered) becomes a candidate decision item; foggy (can't yet be phrased) becomes a labeled Not-yet-specified bullet — rather than answering everything itself or refusing outright."
---

/planning:wayfind chart We started interviewing the overhaul of our entire notification system earlier in this session, but every round opened more branches than it closed. It's way too big to hold in my head, and honestly I don't even know all the questions yet, let alone the answers. Turn this into a map.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read this skill's own files with the Read tool, not Bash.)
