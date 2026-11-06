---
description: "Legacy check eval 8. Asked what skill-quality:check's cross-skill invocation doctrine says about a step calling two skills and a step invoking a :setup skill through the Skill tool, the reply says one Skill call per skill, not to Skill-invoke a disable-model-invocation (user-invoked-only) target but to tell the user to run the slash command, and that the gate does not automate this check. check SKILL.md 'Cross-skill invocation (doctrine)'. one-per-call grades the one-skill-per-call rule; names-user-invoked-only grades disable-model-invocation or user-invoked-only, which the prompt does not say; tells-user-run-slash grades the slash-command route; not-automated judges the whole answer, including that check-skill.sh does not FAIL the reachability class; skill-fired is an indicator."
tags: [skill-quality, check, outcome, read-only, no-network]
max_turns: 8
timeout_seconds: 240
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The reply says the Skill tool takes one skill per call, so two skills are two calls; that a disable-model-invocation (user-invoked-only) target such as a :setup skill must not be invoked through the Skill tool and the user is told to run its slash command instead; and that check-skill.sh does not check this reachability automatically."
---

When reviewing a SKILL.md that says to call two other skills in one step, and also to invoke a :setup skill via the Skill tool, what does skill-quality:check's cross-skill invocation doctrine say?
