---
description: "wayfind evals.json case 36: a prototype item falls back to /planning:design when the prototype plugin is not enabled, says no artifact was built, and records its decision as provisional naming itself (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "With the prototype plugin not enabled, the item falls back to /planning:design. Its resolution comment says no artifact was built, and the decision it settles (Knock) is recorded as provisional, naming this prototype item: its Decisions-so-far line ends 'provisional until' a link to 'Prove Knock sends email and in-app from one call'."
---

/planning:wayfind work 'Map: notification vendor' (#500). The claimed item 'Prove Knock sends email and in-app from one call' (#504, https://github.com/acme/shop/issues/504) carries the wayfind: prototype label. Its body reads: '**Prove:** Knock's API sends one notification to both email and in-app from a single call. **Pass checks:** 1. One API call produces the email. 2. The same call produces the in-app message. **On fail:** reopen the vendor decision. **Fallback:** Courier.' The prototype plugin is not enabled in this repository. No separate vendor decision exists on the map. Work it through to the end.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments) and treat it as made. When that call is /planning:design, take its result as: the discussion settled the vendor on Knock; then carry on with the rest of the item (resolution comment, Decisions-so-far line, close). Put everything in your final reply. Never search for a skill's or plugin's files, and open only those a skill loaded in this session links to; never run Bash, Glob or Grep on a skill or plugin directory.)
