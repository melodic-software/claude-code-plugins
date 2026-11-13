---
description: "Purpose case for the before/after comparison: measures the outcome the replaced guidance served. P5: name the destination and confirm it before any item exists (now ask what done looks like, then propose the whole map)."
tags: [wayfind, wayfind-charting, purpose-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Nothing is created before the user confirms a destination."
---

/planning:wayfind chart the partner-API v2 effort. We interviewed it earlier in this session and it outgrew one sitting. The open questions are auth scheme, rate-limit model and versioning policy, and nobody can yet say what 'partner tiers' should mean.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read this skill's own files with the Read tool, not Bash.)
