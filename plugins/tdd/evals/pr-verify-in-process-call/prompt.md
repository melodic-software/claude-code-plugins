---
description: "Communication-based test on an in-process collaborator. SKILL.md Quick decision guide line 45: 'Output-based first. State-based second. Communication-based only for inter-system with visible side effects.' Line 51 names the cost: a test coupled to implementation details is brittle. The user's test Moq-verifies a call to a pure in-process rules object. The reply moves the assertion to the returned total and limits interaction checks to calls that cross a system boundary. Read-only tools only; no grant needed."
tags: [tdd, principles, outcome, routing, testing-styles]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run invokes the tdd:principles skill. The reply says to assert on the value Total returns (the output, result or total, or names output-based testing), and says interaction or communication checks belong to calls that leave the process or cross a system boundary (out-of-process, unmanaged, external or inter-system dependencies)."
---

I'm unit testing CheckoutService.Total(cart). Inside, it calls an in-process PricingRules object (pure logic, no I/O) to apply discounts. My current test uses Moq to Verify that pricingRules.ApplyDiscounts(cart) was called exactly once. A reviewer pushed back on it. What should the test assert instead, and why?
