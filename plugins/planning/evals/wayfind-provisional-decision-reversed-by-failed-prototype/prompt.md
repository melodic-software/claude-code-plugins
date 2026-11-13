---
description: "wayfind evals.json case 31, run as a plugin-eval case for the before/after comparison (after-only)."
tags: [wayfind, wayfind-charting, after-only]
runs: 3
max_turns: 30
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
expected_outcome: "#504's resolution comment carries the failed verdict. Because the vendor decision rested on that prototype, the failure reverses it through the supersede sweep: a new decision item linking #502 opens, starting from the Courier fallback, #502 is not reopened or edited, and its Decisions-so-far line will point at the superseding decision once that resolves."
---

/planning:wayfind work 'Map: notification vendor' (#500). Decisions-so-far has 'Pick the vendor' (#502): Knock, provisional until 'Prove Knock sends email and in-app from one call' (#504). The claimed prototype #504 just failed: in-app messages need a second call. The prototype's fallback is Courier. Graduate #504.

(Eval harness note, not part of the request: this sandbox has no work-item tracker and no other plugins. Do not stop for that. Take what this message describes as the tracker's current state and make no tracker or `gh` call. Wherever the skill would write to the tracker (create, label, claim, comment, edit a body, wire an edge, close), write each action out in order, with its full text, instead of performing it. Invoke no other skill, this plugin's included: where the skill would invoke one, write out the call (skill and arguments), treat it as made, and stop where that skill would take over the conversation. Put everything in your final reply. Read this skill's own files with the Read tool, not Bash.)
