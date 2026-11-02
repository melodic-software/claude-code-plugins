---
description: "Mock-or-real decision for two out-of-process dependencies. SKILL.md Quick decision guide line 41: 'Should I mock this? Only if it's an unmanaged dependency (message bus, SMTP). Use real instances for managed deps (database).' The service owns its Postgres database (no other system reads it) and publishes to RabbitMQ for another team's service. The reply keeps the database real and mocks the bus. A model without the skill often mocks the repository too, or swaps in an in-memory substitute. Read-only tools only; no grant needed."
tags: [tdd, principles, outcome, routing, mocking]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep]
expected_outcome: "The run invokes the tdd:principles skill. The reply says the tests should use the real Postgres database (a real instance, Testcontainers, or naming it a managed dependency), and says the RabbitMQ publisher or message bus should be mocked, faked or stubbed."
---

I'm writing integration tests for the RegisterUser handler in our ASP.NET Core service. The handler saves the new user to our Postgres database, which only this service reads and writes, and then publishes a UserRegistered event to RabbitMQ, which the billing team's service consumes. Which of those two dependencies should the tests replace with a mock, and which should they use for real? I want the reasoning, not test code.
