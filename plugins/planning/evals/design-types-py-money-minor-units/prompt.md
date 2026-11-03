---
description: "Outcome case: a Python billing repository stores money as a Decimal beside a free-form currency string and pages through a cursor beside a flag. Phase 3 models invoice money as a currency code with an integer count of minor units and a page whose shape cannot hold a flag that disagrees with its cursor"
tags: [design, outcome, type-discipline, python, scaffold]
runs: 3
max_turns: 20
timeout_seconds: 600
allowed_tools: [Read, Skill, Write]
expected_outcome: ".work/invoice-totals/design/type-inventory.md models money as a currency code with an integer count of minor units (for example amount_minor: int, or integer cents) and a results page with no stored has_more flag beside its cursor"
---

/planning:design library

Topic slug `invoice-totals`; the Brief is in `.work/invoice-totals/PLAN.md` and `.work/invoice-totals/design/design-threads.md` holds the settled threads. Threads are settled, so move on to type modeling: write `.work/invoice-totals/design/type-inventory.md`, with each type's definition written out in the repository's language, then stop. Don't write any other file.
