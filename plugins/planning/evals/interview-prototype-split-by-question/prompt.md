---
description: "The interview's outcome is a throwaway prototype that has to settle three unrelated doubts. Why hard: the easy path scopes one prototype that tries to answer everything, or asks only scoping questions, never asking what the prototype must prove or splitting it so the pieces can be built at once."
tags: [interview, prototype, quality-bar]
runs: 3
max_turns: 12
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "The next round asks what the prototype must prove, with a recommendation listing the three doubts as separate questions, and recommends one small prototype per question that can be built at the same time, each in its own worktree"
---

/planning:interview me: resume the new-checkout interview.

[Session state: round 1 is answered and recorded. Q1, the quality bar: the user chose a throwaway prototype. The user said in round 1 they doubt three things: whether the payment provider's test mode supports split payments, whether a one-page checkout layout reads well on a phone, and whether the cart stays responsive with 500 items. Nothing else is settled. Write your next message to the user.]
