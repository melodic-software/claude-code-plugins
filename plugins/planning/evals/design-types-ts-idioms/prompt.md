---
description: "Outcome case: a TypeScript shipment poller needs a retry policy literal set once in code. Phase 3 reads the TypeScript idioms file and holds the literal to its type with satisfies"
tags: [design, outcome, type-discipline, typescript, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Skill, Write]
expected_outcome: "The run reads the skill's TypeScript idioms file, and .work/shipment-poller/design/type-inventory.md holds the retry literal to its type with satisfies"
---

/planning:design library

Topic slug `shipment-poller`; the Brief is in `.work/shipment-poller/PLAN.md` and `.work/shipment-poller/design/design-threads.md` holds the settled threads. Threads are settled, so move on to type modeling: write `.work/shipment-poller/design/type-inventory.md`, with each type's definition, the retry constant and each function signature written out in the repository's language, then stop. Don't write any other file.
