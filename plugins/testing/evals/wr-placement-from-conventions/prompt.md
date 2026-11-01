---
description: "Placement question for a new mapper's tests in a repo whose docs/testing.md sets the layout and one old test sits outside it. The answer follows the documented convention, not the stray example. Hard: the nearest existing file points the wrong way."
tags: [testing, write, organize, outcome, hard, source-skill-contract]
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill]
expected_outcome: "Reads docs/testing.md and answers tests/unit/orders/test_order_mapper.py, because order_mapper is pure code with no database session; it writes no file."
---
/testing:write organize where should the tests for src/orders/order_mapper.py go? Don't write them yet; give me the path and why.
