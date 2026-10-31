---
description: "A teammate wants a charge-call mock assertion deleted because mock assertions are 'always a smell'. The test-value doctrine keeps it: the payment gateway is an unmanaged, state-changing boundary. Hard: the common advice is to drop interaction assertions. Natural phrasing: test-value is not user-invocable."
tags: [testing, test-value, outcome, hard, source-skill-contract]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Keeps the charge assertion, explaining that the gateway is an unmanaged, out-of-process dependency whose state the call changes, so the call is the behavior; it may note that the same assertion on an internal collaborator would only pin the implementation."
---
My teammate says asserting that a mock was called is always a code smell, and wants me to delete the `gateway.charge.assert_called_once_with(...)` line in tests/test_checkout.py. Should I?
