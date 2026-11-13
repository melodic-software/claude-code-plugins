---
description: "Purpose case for the before/after comparison: measures the outcome the replaced guidance served. P1: one sub-issue per sharp question (now one item per topic; ready questions asked in one round)."
tags: [wayfind, wayfind-charting, purpose-set]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "Each of the six open questions is accounted for in the output, inside a proposed or created item or asked of the user; none is dropped or answered by the skill itself."
---

/planning:wayfind chart the partner onboarding effort. We interviewed it earlier in this session and it outgrew one sitting; destination confirmed: a PRD. Six sharp questions are still open, and none has a recommended answer yet. Signup: (1) do partners sign up themselves or only by invitation? (2) which identity fields are mandatory? (3) do we verify the business registration number? Billing setup: (4) monthly or annual invoicing? (5) which currencies at launch? (6) who approves a partner's credit limit? Separately, something bothers me about how partner support hand-offs will work, and I can't put it into words yet.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read any skill's or plugin's files with the Read tool at their exact path; never run Bash, Glob or Grep on a skill or plugin directory.)
