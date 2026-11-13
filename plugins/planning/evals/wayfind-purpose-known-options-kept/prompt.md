---
description: "Purpose case for the before/after comparison: measures the outcome the replaced guidance served. P2: an item body says what must be decided and the options if known (now the question and the criteria an answer must meet, nothing else)."
tags: [wayfind, wayfind-charting, purpose-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "The three known options stay available to whoever later works the backend item: in the item, or in a place the output says that item's worker reads."
---

/planning:wayfind chart the order-search effort. We interviewed it earlier in this session and it outgrew one sitting; destination confirmed: a PRD. One sharp question is open with no recommendation yet: which search backend to use. We already know the three options: Postgres full-text search, OpenSearch, and Typesense. Separately, something about search relevance for business buyers worries me, and I can't phrase it yet.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool at their exact path; never run Bash, Glob or Grep on a skill or plugin directory.)
