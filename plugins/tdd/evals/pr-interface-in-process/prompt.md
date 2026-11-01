---
description: "Hard case. Interface for an in-process dependency. SKILL.md Quick decision guide line 47: 'Should I introduce an interface? Only for unmanaged deps you need to mock. Concrete classes for managed deps. Never for in-process deps.' Line 41 backs it: mock only unmanaged dependencies. The teammate wants an interface over a pure, in-process calculator so tests can mock it. The reply answers no and keeps the real class in the tests. Hard because extracting an interface 'for testability' is the common default a model without the skill reaches for. Read-only tools only; no grant needed."
tags: [tdd, principles, outcome, routing, interfaces, hard]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run invokes the tdd:principles skill. The reply opens with a no verdict (or says not to extract or introduce the interface), and says the OrderService tests should use the real or concrete DiscountCalculator."
---

In our C# order service, OrderService takes a DiscountCalculator in its constructor. DiscountCalculator is a plain in-process class: pure pricing logic, no I/O, one implementation. A teammate wants to extract an IDiscountCalculator interface so the OrderService unit tests can mock it. Is that a good idea? Answer yes or no first, then explain.
